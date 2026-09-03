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
from app.modules.interviews.facts import DeterministicFactExtractor, FactSource
from app.modules.interviews.model import InterviewAnswer, InterviewSession  # noqa: F401
from app.modules.interviews.question_generator import DeterministicQuestionGenerator
from app.modules.interviews.schemas import InterviewCreateRequest
from app.modules.interviews.service import InterviewService
from app.modules.prompt_engine.builder import PromptBuilder
from app.modules.prompt_engine.enums import PromptCategory, PromptMode
from app.modules.prompt_engine.schemas import PromptGenerateRequest
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


def test_case_a_keeps_questions_when_initial_request_has_no_safe_facts() -> None:
    extractor = DeterministicFactExtractor()
    facts = extractor.extract("Quero criar um anúncio para vender um tênis feminino.", PromptCategory.MARKETING)
    questions = DeterministicQuestionGenerator().generate(PromptMode.PRO, PromptCategory.MARKETING, set(facts))
    assert facts == {}
    assert [question.key for question in questions] == ["channel", "cta", "audience", "tone"]


def test_case_b_extracts_safe_facts_and_omits_redundant_questions() -> None:
    extractor = DeterministicFactExtractor()
    facts = extractor.extract(
        "Quero criar um anúncio para Instagram para mulheres de 18 a 35 anos com tom persuasivo.",
        PromptCategory.MARKETING,
    )
    assert facts["channel"].value == "rede social"
    assert facts["channel"].detail == "Instagram"
    assert facts["audience"].value == "mulheres de 18 a 35 anos"
    assert facts["tone"].value == "persuasivo"
    assert all(fact.source == FactSource.INITIAL_REQUEST for fact in facts.values())
    questions = DeterministicQuestionGenerator().generate(PromptMode.PRO, PromptCategory.MARKETING, set(facts))
    assert [question.key for question in questions] == ["cta"]


@pytest.mark.parametrize(
    ("input_text", "expected"),
    [
        ("campanha voltada para empresas da região", "empresas da região"),
        ("anúncio direcionado para restaurantes", "restaurantes"),
        ("conteúdo destinado a profissionais de saúde", "profissionais de saúde"),
        ("campanha voltada às pequenas empresas", "pequenas empresas"),
    ],
)
def test_extracts_audience_from_explicit_direction_without_specializing_it(
    input_text: str,
    expected: str,
) -> None:
    facts = DeterministicFactExtractor().extract(
        input_text,
        PromptCategory.MARKETING,
    )

    assert facts["audience"].value == expected
    assert facts["audience"].source == FactSource.INITIAL_REQUEST


def test_cases_c_and_d_extract_category_specific_facts() -> None:
    extractor = DeterministicFactExtractor()
    video = extractor.extract(
        "Crie um vídeo para TikTok de 15 segundos para divulgar uma pizzaria para jovens.",
        PromptCategory.VIDEO,
    )
    assert video["platform"].value == "TikTok"
    assert video["duration"].value == "15 segundos"
    assert video["audience"].value == "jovens"

    programming = extractor.extract(
        "Crie um site em React para uma pizzaria com cardápio e botão de WhatsApp.",
        PromptCategory.PROGRAMMING,
    )
    assert programming["stack"].value == "React"
    assert programming["platform"].value == "site"


def test_expert_question_limit_and_dynamic_total() -> None:
    generator = DeterministicQuestionGenerator()
    full = generator.generate(PromptMode.EXPERT, PromptCategory.MARKETING)
    adaptive = generator.generate(PromptMode.EXPERT, PromptCategory.MARKETING, {"channel", "audience", "tone"})
    assert len(full) <= generator.MAX_EXPERT_QUESTIONS
    assert len(adaptive) == len(full) - 3


def test_form_facts_are_explicit_and_override_extracted_values() -> None:
    extractor = DeterministicFactExtractor()
    extracted = extractor.extract("Anúncio com tom profissional", PromptCategory.MARKETING)
    form = extractor.from_form(
        PromptGenerateRequest(
            input="Anúncio com tom profissional",
            mode="pro",
            category="marketing",
            tone="persuasivo",
            audience="Clientes recorrentes",
            context="Campanha de lançamento",
        )
    )
    extracted.update(form)
    assert extracted["tone"].value == "persuasivo"
    assert extracted["tone"].source == FactSource.FORM
    assert extracted["audience"].source == FactSource.FORM


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
