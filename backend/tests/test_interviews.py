from collections.abc import AsyncGenerator
from datetime import UTC, datetime, timedelta

import pytest
import pytest_asyncio
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.db.base import Base
from app.modules.auth.model import PasswordResetToken, RefreshToken  # noqa: F401
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
from app.modules.interviews.enums import QuestionType
from app.modules.interviews.model import InterviewAnswer, InterviewSession  # noqa: F401
from app.modules.interviews.question_generator import DeterministicQuestionGenerator
from app.modules.interviews.schemas import InterviewCreateRequest
from app.modules.interviews.service import InterviewService
from app.modules.prompt_engine.builder import PromptBuilder
from app.modules.prompt_engine.enums import PromptCategory, PromptMode
from app.modules.users.model import User
from app.modules.users.roles import Role


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


def test_deterministic_questions_cover_categories_modes_and_types() -> None:
    generator = DeterministicQuestionGenerator()
    types = set()
    for category in PromptCategory:
        assert generator.generate(PromptMode.BASIC, category) == []
        pro = generator.generate(PromptMode.PRO, category)
        expert = generator.generate(PromptMode.EXPERT, category)
        assert len(pro) == 4
        assert len(expert) > len(pro)
        assert len({question.key for question in expert}) == len(expert)
        types.update(question.type for question in expert)
    assert types == set(QuestionType)


@pytest.mark.asyncio
async def test_expired_interview_rejects_access_and_uses_no_ai_gateway(
    session_factory: async_sessionmaker[AsyncSession],
) -> None:
    async with session_factory() as session:
        user = User(
            email="expired@example.com",
            full_name="Expired User",
            hashed_password="not-used",
            role=Role.USER,
            is_active=True,
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        service = InterviewService(session)
        created = await service.start(
            user,
            InterviewCreateRequest(initial_request="Criar uma campanha", mode="pro", category="marketing"),
        )
        model = await service.repository.get_by_id(created.id)
        assert model is not None
        model.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        await session.commit()

        with pytest.raises(HTTPException) as error:
            await service.get(created.id, user)
        assert error.value.status_code == 409
        expired = await service.repository.get_by_id(created.id)
        assert expired is not None and expired.status == "expired"


@pytest.mark.asyncio
async def test_completed_payload_is_accepted_by_deterministic_prompt_builder(
    session_factory: async_sessionmaker[AsyncSession],
) -> None:
    async with session_factory() as session:
        user = User(
            email="builder@example.com",
            full_name="Builder User",
            hashed_password="not-used",
            role=Role.USER,
            is_active=True,
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        service = InterviewService(session)
        created = await service.start(
            user,
            InterviewCreateRequest(initial_request="Resuma este tema", mode="basic", category="geral"),
        )
        completed = await service.complete(created.id, user)
        built = PromptBuilder().build(completed.prompt_input)
        assert "## OBJECTIVE\nResuma este tema" in built
        assert completed.prompt_input.optimize_with_ai is False
