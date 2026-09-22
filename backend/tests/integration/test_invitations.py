from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock
from uuid import UUID, uuid4

import jwt
import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.main import app
from app.modules.auth.model import RefreshToken
from app.modules.auth.registration import require_registration_access
from app.modules.auth.service import AuthService
from app.modules.billing.model import Subscription, UsageRecord
from app.modules.billing.service import BillingService
from app.modules.credits.model import CreditReservation, CreditTransaction, CreditWallet
from app.modules.credits.service import CreditService
from app.modules.users.model import User
from app.modules.users.repository import UserRepository
from app.modules.users.schemas import AdminUserCreate

EMAIL = 'invited@example.com'
PASSWORD = 'SecurePassword123!'


@pytest.fixture
def issuer(client, session_factory):
    async def provision():
        async with session_factory() as session:
            user = await AuthService(session).register(AdminUserCreate(
                email='issuer@example.com', full_name='Pilot Administrator', password=PASSWORD, role='admin',
            ))
            return user.id

    user_id = client.portal.call(provision)
    response = client.post('/api/v1/auth/login', json={'email': 'issuer@example.com', 'password': PASSWORD})
    assert response.status_code == 200
    app.dependency_overrides.pop(require_registration_access)
    return user_id, {'Authorization': f"Bearer {response.json()['access_token']}"}


def invitation(client, issuer):
    response = client.post('/api/v1/auth/invitations', headers=issuer[1], json={'email': EMAIL})
    assert response.status_code == 201
    assert response.headers['cache-control'] == 'no-store'
    return response.json()['invitation_token']


def signup(client, token, **extra):
    return client.post('/api/v1/auth/register', json={
        'email': EMAIL, 'full_name': 'Pilot Invitee', 'password': PASSWORD, 'invitation_token': token, **extra,
    })


def counts(client, session_factory):
    async def read():
        async with session_factory() as session:
            return [await session.scalar(select(func.count()).select_from(model)) for model in (
                User, Subscription, CreditWallet, CreditTransaction, RefreshToken, UsageRecord, CreditReservation,
            )]
    return client.portal.call(read)


def test_invitation_issues_without_grants_and_signup_grants_once(client, session_factory, issuer):
    before = counts(client, session_factory)
    token = invitation(client, issuer)
    after_issue = counts(client, session_factory)
    assert after_issue == [*before[:4], before[4] + 1, *before[5:]]
    settings = get_settings()
    claims = jwt.decode(
        token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm], audience='pilot-registration',
    )
    assert claims['exp'] - claims['iat'] == 72 * 60 * 60
    assert claims['sub'] == EMAIL
    assert claims['type'] == 'invitation'

    response = signup(client, token, role='admin', is_active=False)
    assert response.status_code == 201
    assert response.headers['cache-control'] == 'no-store'
    data = response.json()
    assert data['user']['role'] == 'user'
    assert data['user']['is_active'] is True
    assert set(data['user']) == {'id', 'email', 'full_name', 'is_active', 'role', 'created_at'}
    assert token not in response.text
    uid = UUID(data['user']['id'])

    async def verify():
        async with session_factory() as session:
            subscription = await session.scalar(select(Subscription).where(Subscription.user_id == uid))
            wallet = await session.scalar(select(CreditWallet).where(CreditWallet.user_id == uid))
            grants = list((await session.scalars(select(CreditTransaction).where(
                CreditTransaction.user_id == uid,
            ))).all())
            consumed = await session.scalar(select(RefreshToken).where(RefreshToken.token_jti == claims['jti']))
            assert subscription.status == 'trialing'
            assert len(grants) == 1 and grants[0].type == 'trial_grant'
            assert wallet.available_balance == grants[0].amount == 100
            assert wallet.reserved_balance == 0
            assert consumed.user_id == issuer[0] and consumed.revoked_at is not None

    client.portal.call(verify)
    after_signup = counts(client, session_factory)
    assert after_signup[-2:] == [0, 0]
    assert signup(client, token).status_code == 403
    assert counts(client, session_factory) == after_signup
    assert client.post('/api/v1/auth/login', json={'email': EMAIL, 'password': PASSWORD}).status_code == 200


@pytest.mark.parametrize('case', [
    'tampered', 'expired', 'wrong_email', 'wrong_type', 'wrong_audience', 'unknown_jti', 'missing_exp',
])
def test_invalid_invitation_never_provisions(client, session_factory, issuer, monkeypatch, case):
    token = invitation(client, issuer)
    settings = get_settings()
    claims = jwt.decode(
        token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm], audience='pilot-registration',
    )
    if case == 'expired':
        claims['exp'] = datetime.now(UTC) - timedelta(seconds=1)
    elif case == 'wrong_email':
        claims['sub'] = 'another@example.com'
    elif case == 'wrong_type':
        claims['type'] = 'access'
    elif case == 'wrong_audience':
        claims['aud'] = 'another-purpose'
    elif case == 'unknown_jti':
        claims['jti'] = f'inv:{uuid4().hex}'
    elif case == 'missing_exp':
        del claims['exp']
    token = jwt.encode(claims, 'different-test-key' * 3 if case == 'tampered' else settings.jwt_secret_key,
                       algorithm=settings.jwt_algorithm)
    before = counts(client, session_factory)
    guards = []
    for owner, method in [(UserRepository, 'create'), (BillingService, 'provision_trial'),
                          (CreditService, 'grant_trial'), (AsyncSession, 'commit')]:
        guard = AsyncMock(side_effect=AssertionError('Invalid invitation reached a write'))
        monkeypatch.setattr(owner, method, guard)
        guards.append(guard)
    response = signup(client, token)
    assert response.status_code == 403
    assert response.json() == {'detail': 'Registration requires an invitation'}
    assert token not in response.text
    for guard in guards:
        guard.assert_not_called()
    assert counts(client, session_factory) == before


@pytest.mark.parametrize('case', ['inactive', 'demoted', 'revoked', 'database_expired'])
def test_invitation_checks_current_database_authorization(client, session_factory, issuer, case):
    token = invitation(client, issuer)

    async def invalidate():
        async with session_factory() as session:
            user = await session.get(User, issuer[0])
            row = await session.scalar(select(RefreshToken).where(RefreshToken.token_jti.like('inv:%')))
            if case == 'inactive':
                user.is_active = False
            elif case == 'demoted':
                user.role = 'user'
            elif case == 'revoked':
                row.revoked_at = datetime.now(UTC)
            else:
                row.expires_at = datetime.now(UTC) - timedelta(seconds=1)
            await session.commit()

    client.portal.call(invalidate)
    before = counts(client, session_factory)
    assert signup(client, token).status_code == 403
    assert counts(client, session_factory) == before


@pytest.mark.parametrize('action', ['email_change', 'delete'])
def test_consumed_invitation_cannot_be_reused_after_account_changes(client, session_factory, issuer, action):
    token = invitation(client, issuer)
    registered = signup(client, token)
    assert registered.status_code == 201
    uid = UUID(registered.json()['user']['id'])

    async def change():
        async with session_factory() as session:
            user = await session.get(User, uid)
            if action == 'email_change':
                user.email = 'changed@example.com'
            else:
                await session.delete(user)
            await session.commit()

    client.portal.call(change)
    before = counts(client, session_factory)
    assert signup(client, token).status_code == 403
    assert counts(client, session_factory) == before


def test_registration_failure_rolls_back_grant_and_consumption(client, session_factory, issuer, monkeypatch):
    token = invitation(client, issuer)
    before = counts(client, session_factory)
    original = CreditService.grant_trial

    async def grant_then_fail(self, subscription):
        await original(self, subscription)
        raise RuntimeError('isolated failure after credit grant')

    with monkeypatch.context() as patch:
        patch.setattr(CreditService, 'grant_trial', grant_then_fail)
        with pytest.raises(RuntimeError, match='isolated failure'):
            signup(client, token)
    assert counts(client, session_factory) == before
    assert signup(client, token).status_code == 201


@pytest.mark.parametrize('identity,expected', [('anonymous', 401), ('user', 403), ('inactive_admin', 401)])
def test_only_active_admin_can_issue_invitation(client, session_factory, issuer, identity, expected):
    headers = issuer[1]
    if identity == 'anonymous':
        headers = {}
    else:
        async def change_role():
            async with session_factory() as session:
                user = await session.get(User, issuer[0])
                if identity == 'user':
                    user.role = 'user'
                else:
                    user.is_active = False
                await session.commit()
        client.portal.call(change_role)
    before = counts(client, session_factory)
    assert client.post('/api/v1/auth/invitations', headers=headers, json={'email': EMAIL}).status_code == expected
    assert counts(client, session_factory) == before


def test_invitation_is_not_an_access_or_refresh_token(client, issuer):
    token = invitation(client, issuer)
    assert client.get('/api/v1/users/me', headers={'Authorization': f'Bearer {token}'}).status_code == 401
    assert client.post('/api/v1/auth/refresh', json={'refresh_token': token}).status_code == 401


def test_duplicate_email_keeps_invitation_unused(client, session_factory, issuer):
    first, second = invitation(client, issuer), invitation(client, issuer)
    assert signup(client, first).status_code == 201
    before = counts(client, session_factory)
    assert signup(client, second).status_code == 409
    assert counts(client, session_factory) == before
    assert client.post('/api/v1/auth/invitations', headers=issuer[1], json={'email': EMAIL}).status_code == 409
