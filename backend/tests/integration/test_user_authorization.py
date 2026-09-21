from unittest.mock import AsyncMock
from uuid import UUID, uuid4

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.auth.service import AuthService
from app.modules.users.model import User
from app.modules.users.repository import UserRepository
from app.modules.users.schemas import AdminUserCreate


def register(client, email):
    response = client.post('/api/v1/auth/register', json={
        'email': email, 'full_name': 'Authorization Test', 'password': 'SecurePassword123!',
    })
    assert response.status_code == 201
    return response.json()


@pytest.mark.parametrize('identity', ['anonymous', 'invalid_token', 'self', 'other', 'missing'])
@pytest.mark.parametrize('payload', [
    {'is_active': False}, {'is_active': None}, {'role': 'admin'}, {'role': None},
    {'full_name': 'Changed', 'is_active': True}, {'hashed_password': 'injected'},
    {'id': str(uuid4())}, {'permissions': ['users:manage']},
])
def test_patch_denies_forbidden_fields_without_update_or_commit(
    client, session_factory, monkeypatch, identity, payload,
):
    caller = register(client, 'caller@example.com')
    target = register(client, 'target@example.com')
    target_id = caller['user']['id'] if identity == 'self' else target['user']['id']
    path_id = str(uuid4()) if identity == 'missing' else target_id
    headers = {} if identity == 'anonymous' else {
        'Authorization': 'Bearer invalid' if identity == 'invalid_token' else f"Bearer {caller['access_token']}",
    }
    update = AsyncMock(side_effect=AssertionError('Denied request reached update'))
    commit = AsyncMock(side_effect=AssertionError('Denied request reached commit'))
    monkeypatch.setattr(UserRepository, 'update', update)
    monkeypatch.setattr(AsyncSession, 'commit', commit)

    response = client.patch(f'/api/v1/users/{path_id}', headers=headers, json=payload)

    assert response.status_code == (401 if identity in {'anonymous', 'invalid_token'} else 403)
    if response.status_code == 403:
        assert response.json() == {'detail': 'Insufficient permissions'}
    for secret in ('hashed_password', 'SecurePassword123!', caller['access_token'], 'Traceback', 'AttributeError'):
        assert secret not in response.text
    update.assert_not_called()
    commit.assert_not_called()

    async def read():
        async with session_factory() as session:
            user = await session.get(User, UUID(target_id))
            return user.is_active, user.full_name

    assert client.portal.call(read) == (True, 'Authorization Test')


@pytest.mark.parametrize('identity', ['self', 'other', 'missing', 'anonymous'])
def test_profile_fields_authorization(client, session_factory, monkeypatch, identity):
    caller = register(client, 'caller@example.com')
    target = register(client, 'target@example.com')
    path_id = {
        'self': caller['user']['id'], 'other': target['user']['id'],
        'missing': str(uuid4()), 'anonymous': caller['user']['id'],
    }[identity]
    headers = {} if identity == 'anonymous' else {'Authorization': f"Bearer {caller['access_token']}"}
    if identity != 'self':
        update = AsyncMock()
        commit = AsyncMock()
        monkeypatch.setattr(UserRepository, 'update', update)
        monkeypatch.setattr(AsyncSession, 'commit', commit)
    response = client.patch(f'/api/v1/users/{path_id}', headers=headers,
                            json={'full_name': 'Updated Profile', 'email': 'updated@example.com'})
    assert response.status_code == (200 if identity == 'self' else 401 if identity == 'anonymous' else 403)
    if identity != 'self':
        update.assert_not_called()
        commit.assert_not_called()
        return
    assert set(response.json()) == {'id', 'email', 'full_name', 'is_active', 'role', 'created_at'}

    async def read():
        async with session_factory() as session:
            user = await session.get(User, UUID(path_id))
            return user.full_name, user.email, user.role, user.is_active

    assert client.portal.call(read) == ('Updated Profile', 'updated@example.com', 'user', True)
    # Keeping the current email is allowed as well.
    assert client.patch(f'/api/v1/users/{path_id}', headers=headers,
                        json={'email': 'updated@example.com'}).status_code == 200


@pytest.mark.parametrize('admin', [False, True])
def test_patch_preserves_conflict_and_admin_not_found(client, session_factory, monkeypatch, admin):
    caller = register(client, 'caller@example.com')
    register(client, 'taken@example.com')
    if admin:
        async def create_admin():
            async with session_factory() as session:
                await AuthService(session).register(AdminUserCreate(
                    email='admin@example.com', full_name='Admin', password='SecurePassword123!', role='admin',
                ))
        client.portal.call(create_admin)
        token = client.post('/api/v1/auth/login', json={
            'email': 'admin@example.com', 'password': 'SecurePassword123!',
        }).json()['access_token']
    else:
        token = caller['access_token']
    headers = {'Authorization': f'Bearer {token}'}
    update = AsyncMock()
    commit = AsyncMock()
    monkeypatch.setattr(UserRepository, 'update', update)
    monkeypatch.setattr(AsyncSession, 'commit', commit)
    response = client.patch(f"/api/v1/users/{caller['user']['id']}", headers=headers,
                            json={'email': 'taken@example.com'})
    assert response.status_code == 409
    response = client.patch(f'/api/v1/users/{uuid4()}', headers=headers, json={'full_name': 'Changed'})
    assert response.status_code == (404 if admin else 403)
    if admin:
        response = client.patch(f"/api/v1/users/{caller['user']['id']}", headers=headers,
                                json={'hashed_password': 'injected', 'full_name': 'Changed'})
        assert response.status_code == 403
        assert response.json() == {'detail': 'Insufficient permissions'}
    update.assert_not_called()
    commit.assert_not_called()


def test_admin_patch_persists_and_inactive_account_cannot_authenticate(client, session_factory):
    # Official service provisions the administrator only in isolated SQLite fixtures.
    async def create_admin():
        async with session_factory() as session:
            return await AuthService(session).register(AdminUserCreate(
                email='admin@example.com', full_name='Test Administrator',
                password='SecurePassword123!', role='admin',
            ))

    client.portal.call(create_admin)
    login = client.post('/api/v1/auth/login', json={
        'email': 'admin@example.com', 'password': 'SecurePassword123!',
    })
    assert login.status_code == 200
    headers = {'Authorization': f"Bearer {login.json()['access_token']}"}
    admin_id = client.get('/api/v1/users/me', headers=headers).json()['id']
    assert client.patch(f'/api/v1/users/{admin_id}', headers=headers,
                        json={'full_name': 'Updated Administrator'}).status_code == 200
    target = register(client, 'target@example.com')
    target_id = target['user']['id']

    response = client.patch(f'/api/v1/users/{target_id}', headers=headers,
                            json={'is_active': False, 'full_name': 'Disabled Test Account',
                                  'role': 'admin', 'email': 'disabled@example.com'})
    assert response.status_code == 200
    assert response.json()['is_active'] is False
    assert set(response.json()) == {'id', 'email', 'full_name', 'is_active', 'role', 'created_at'}

    async def read():
        async with session_factory() as session:
            user = await session.get(User, UUID(target_id))
            return user.is_active, user.full_name, user.role, user.email

    assert client.portal.call(read) == (False, 'Disabled Test Account', 'admin', 'disabled@example.com')
    assert client.post('/api/v1/auth/login', json={
        'email': 'disabled@example.com', 'password': 'SecurePassword123!',
    }).status_code == 403
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': target['refresh_token']}).status_code == 403
    assert client.get('/api/v1/users/me', headers={
        'Authorization': f"Bearer {target['access_token']}",
    }).status_code == 401
    assert client.patch(f'/api/v1/users/{admin_id}', headers={
        'Authorization': f"Bearer {target['access_token']}",
    }, json={'full_name': 'Forbidden'}).status_code == 401
