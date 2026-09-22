from collections.abc import AsyncGenerator, Generator

import pytest
import pytest_asyncio
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.db.base import Base
from app.db.session import get_db_session
from app.main import app
from app.modules.auth import router as auth_router
from app.modules.auth.model import PasswordResetToken, RefreshToken  # noqa: F401
from app.modules.auth.registration import InvitationClaims, register_invited, require_registration_access
from app.modules.auth.schemas import RegistrationResponse
from app.modules.auth.service import AuthService
from app.modules.billing.model import Plan, Subscription, UsageRecord  # noqa: F401
from app.modules.credits.model import (  # noqa: F401
    CreditCostRule,
    CreditLot,
    CreditPackage,
    CreditReservation,
    CreditReservationAllocation,
    CreditTransaction,
    CreditWallet,
)
from app.modules.interviews.model import InterviewAnswer, InterviewSession  # noqa: F401
from app.modules.payments.model import Payment, PaymentEvent  # noqa: F401
from app.modules.prompt_engine.model import Prompt  # noqa: F401
from app.modules.users.model import User  # noqa: F401


@pytest_asyncio.fixture
async def session_factory() -> AsyncGenerator[async_sessionmaker[AsyncSession]]:
    engine = create_async_engine(
        "sqlite+aiosqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    yield async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    await engine.dispose()


@pytest.fixture
def client(session_factory: async_sessionmaker[AsyncSession], monkeypatch) -> Generator[TestClient]:
    async def override_session() -> AsyncGenerator[AsyncSession]:
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db_session] = override_session
    # Existing feature tests provision isolated accounts, not public pilot signups.
    # Registration-access regressions remove this override to test the real gate.
    fixture_admission = InvitationClaims(jti="fixture-only", email="fixture-only")
    app.dependency_overrides[require_registration_access] = lambda: fixture_admission

    async def register_fixture_or_invited(session, data, invitation):
        if invitation is not fixture_admission:
            return await register_invited(session, data, invitation)
        service = AuthService(session)
        user = await service.register(data)
        tokens = await service.issue_tokens(user)
        return RegistrationResponse(**tokens.model_dump(), user=user)

    monkeypatch.setattr(auth_router, "register_invited", register_fixture_or_invited)
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
