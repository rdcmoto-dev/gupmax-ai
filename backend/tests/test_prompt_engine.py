from types import SimpleNamespace
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.modules.ai_gateway.schemas import GenerateTextResponse, TokenUsageResponse
from app.modules.prompt_engine.builder import PromptBuilder
from app.modules.prompt_engine.enums import PromptCategory, PromptMode, PromptStatus
from app.modules.prompt_engine.schemas import PromptGenerateRequest
from app.modules.prompt_engine.service import PromptService
from app.modules.users.roles import Role


def test_builder_produces_deterministic_professional_sections() -> None:
    data = PromptGenerateRequest(
        input="Crie um anúncio para vender tênis feminino",
        category="marketing",
        language="pt-BR",
        tone="persuasivo",
        mode="pro",
        context="Lançamento de primavera",
        audience="Mulheres que praticam corrida",
        output_format="Título e texto de até 100 palavras",
    )

    first = PromptBuilder().build(data)
    second = PromptBuilder().build(data)

    assert first == second
    assert "## ROLE" in first
    assert "## OBJECTIVE" in first
    assert "## CONTEXT" in first
    assert "## AUDIENCE" in first
    assert "## INSTRUCTIONS" in first
    assert "## OUTPUT FORMAT" in first
    assert "## LANGUAGE\npt-BR" in first
    assert "## TONE\npersuasivo" in first


def test_builder_modes_control_detail() -> None:
    basic = PromptBuilder().build(PromptGenerateRequest(input="Resuma este assunto", mode="basic"))
    expert = PromptBuilder().build(
        PromptGenerateRequest(input="Resuma este assunto", mode="expert", constraints=["Não invente dados"])
    )
    assert "## CONTEXT" not in basic
    assert "## CONSTRAINTS" not in basic
    assert "## CONSTRAINTS" in expert
    assert "Não invente dados" in expert


@pytest.mark.parametrize(
    ("field", "value"),
    [("input", "x"), ("input", "x" * 10_001), ("language", "invalid_language"), ("instructions", ["x" * 501])],
)
def test_generate_schema_rejects_excessive_or_invalid_payloads(field: str, value: object) -> None:
    with pytest.raises(ValidationError):
        PromptGenerateRequest(**{"input": "entrada válida", field: value})


class FakeGateway:
    async def generate(self, _data: object) -> GenerateTextResponse:
        return GenerateTextResponse(
            provider="fake",
            model="test-model",
            text="PROMPT OTIMIZADO",
            latency_ms=1,
            usage=TokenUsageResponse(input_tokens=10, output_tokens=4, total_tokens=14),
        )


@pytest.mark.asyncio
async def test_service_optimizes_only_through_injected_gateway() -> None:
    service = PromptService(SimpleNamespace(), FakeGateway())
    saved: dict[str, object] = {}

    async def fake_create(**values: object) -> SimpleNamespace:
        saved.update(values)
        now = __import__("datetime").datetime.now(__import__("datetime").UTC)
        return SimpleNamespace(id=uuid4(), created_at=now, updated_at=now, **values)

    service.repository.create = fake_create
    user = SimpleNamespace(id=uuid4(), role=Role.USER)
    response = await service.generate(
        user, PromptGenerateRequest(input="Crie uma campanha", optimize_with_ai=True, mode=PromptMode.PRO)
    )

    assert response.generated_prompt == "PROMPT OTIMIZADO"
    assert response.status == PromptStatus.OPTIMIZED
    assert response.provider == "fake"
    assert response.usage is not None and response.usage.total_tokens == 14
    assert saved["total_tokens"] == 14
    assert saved["category"] == PromptCategory.GENERAL
