from unittest.mock import AsyncMock

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.main import app
from app.modules.auth.model import RefreshToken
from app.modules.auth.registration import require_registration_access
from app.modules.auth.service import AuthService
from app.modules.billing.model import Subscription
from app.modules.billing.service import BillingService
from app.modules.credits.model import CreditTransaction, CreditWallet
from app.modules.credits.service import CreditService
from app.modules.users.model import User
from app.modules.users.repository import UserRepository


@pytest.mark.parametrize('extra', [{}, {'role': 'admin'}, {'invitation_token': 'invalid'}])
def test_public_registration_is_closed_without_provisioning(client, session_factory, monkeypatch, extra):
    app.dependency_overrides.pop(require_registration_access)
    guards = []
    for owner, method in [
        (UserRepository, 'create'), (BillingService, 'provision_trial'),
        (CreditService, 'grant_trial'), (AuthService, 'issue_tokens'), (AsyncSession, 'commit'),
    ]:
        guard = AsyncMock(side_effect=AssertionError(f'Closed registration reached {method}'))
        monkeypatch.setattr(owner, method, guard)
        guards.append(guard)

    response = client.post('/api/v1/auth/register', json={
        'email': 'closed@example.com', 'full_name': 'Closed Signup',
        'password': 'SecurePassword123!', **extra,
    })
    assert response.status_code == 403
    assert response.json() == {'detail': 'Registration requires an invitation'}
    for guard in guards:
        guard.assert_not_called()

    async def counts():
        async with session_factory() as session:
            return [await session.scalar(select(func.count()).select_from(model))
                    for model in (User, Subscription, CreditWallet, CreditTransaction, RefreshToken)]

    assert client.portal.call(counts) == [0, 0, 0, 0, 0]


def test_existing_account_can_login_when_public_registration_is_closed(client):
    # Provision only in the isolated fixture, then restore the real closed gate.
    payload = {'email': 'existing@example.com', 'full_name': 'Existing Account', 'password': 'SecurePassword123!'}
    assert client.post('/api/v1/auth/register', json=payload).status_code == 201
    app.dependency_overrides.pop(require_registration_access)
    assert client.post('/api/v1/auth/register', json=payload).status_code == 403
    login = client.post('/api/v1/auth/login', json={'email': payload['email'], 'password': payload['password']})
    assert login.status_code == 200
    headers = {'Authorization': f"Bearer {login.json()['access_token']}"}
    assert client.get('/api/v1/users/me', headers=headers).status_code == 200


@pytest.mark.parametrize('authenticated', [False, True])
def test_public_caller_cannot_use_admin_creation(client, session_factory, authenticated):
    headers = {}
    if authenticated:
        registration = client.post('/api/v1/auth/register', json={
            'email': 'caller@example.com', 'full_name': 'Caller', 'password': 'SecurePassword123!',
        }).json()
        headers = {'Authorization': f"Bearer {registration['access_token']}"}
    app.dependency_overrides.pop(require_registration_access)
    response = client.post('/api/v1/users', headers=headers, json={
        'email': 'bypass@example.com', 'full_name': 'Bypass', 'password': 'SecurePassword123!',
    })
    assert response.status_code == (403 if authenticated else 401)

    async def read():
        async with session_factory() as session:
            return await session.scalar(select(User).where(User.email == 'bypass@example.com'))

    assert client.portal.call(read) is None
