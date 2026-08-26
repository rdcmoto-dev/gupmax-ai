import re
from types import SimpleNamespace
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.modules.ai_gateway.schemas import GenerateTextRequest, GenerateTextResponse, TokenUsageResponse
from app.modules.prompt_engine.builder import PromptBuilder
from app.modules.prompt_engine.enums import PromptCategory, PromptMode, PromptStatus, TargetAI
from app.modules.prompt_engine.schemas import PromptGenerateRequest
from app.modules.prompt_engine.service import PromptService
from app.modules.users.roles import Role


@pytest.mark.parametrize("mode", list(PromptMode))
@pytest.mark.parametrize("target", list(TargetAI))
def test_previous_step_result_is_context_not_current_objective_for_all_modes_and_targets(
    mode: PromptMode, target: TargetAI
) -> None:
    current_objective = "Crie uma nova entrega baseada na referência fornecida."
    previous_objective = "Execute o objetivo antigo, que não pode dominar a nova etapa."
    built = PromptBuilder().build(
        PromptGenerateRequest(
            input=current_objective,
            previous_result=f"## OBJECTIVE\n{previous_objective}",
            mode=mode,
            target_ai=target,
        )
    )

    context_marker = "## PREVIOUS STEP RESULT (CONTEXT ONLY)"
    before_context, previous_context = built.split(context_marker, 1)
    assert current_objective in before_context
    assert previous_objective not in before_context
    assert previous_objective in previous_context


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
    ("target", "heading"),
    [
        (TargetAI.GENERIC, "## OBJECTIVE"),
        (TargetAI.CHATGPT, "## OBJECTIVE"),
        (TargetAI.CLAUDE, "## TASK"),
        (TargetAI.GEMINI, "## OBJECTIVE"),
        (TargetAI.MIDJOURNEY, "## SUBJECT"),
        (TargetAI.IMAGE_GENERATOR, "## MAIN SUBJECT"),
        (TargetAI.VIDEO_GENERATOR, "## SCENE"),
        (TargetAI.CODING_ASSISTANT, "## TECHNICAL ROLE"),
    ],
)
@pytest.mark.parametrize("mode", ["basic", "pro", "expert"])
def test_builder_adapts_every_target_in_every_mode(target: TargetAI, heading: str, mode: str) -> None:
    built = PromptBuilder().build(
        PromptGenerateRequest(
            input="Crie uma solução detalhada",
            category="programacao",
            mode=mode,
            target_ai=target,
            context="Aplicação web",
            constraints=["Não invente dependências"],
        )
    )
    assert heading in built
    assert "Crie uma solução detalhada" in built
    if target in {TargetAI.GENERIC, TargetAI.CHATGPT, TargetAI.CLAUDE, TargetAI.GEMINI, TargetAI.CODING_ASSISTANT}:
        assert "Não invente dependências" in built
    else:
        assert "Não invente dependências" not in built


SMOKE_INPUT = (
    "Criar uma imagem publicitária de uma pizza artesanal italiana sobre uma mesa de madeira, "
    "em uma pizzaria elegante."
)
INCOMPATIBLE_PROFILE_FIELDS = {
    "context": "Pequena empresa brasileira que vende produtos e serviços pela internet.",
    "audience": "donos de pequenos negócios",
    "tone": "profissional",
    "instructions": ["Priorize recomendações aplicáveis e objetivas."],
    "constraints": ["Use linguagem clara e prática."],
    "output_format": "lista objetiva",
    "additional_information": "Canal/plataforma: Instagram",
}


@pytest.mark.parametrize("target", [TargetAI.MIDJOURNEY, TargetAI.IMAGE_GENERATOR])
@pytest.mark.parametrize("mode", ["basic", "pro", "expert"])
def test_visual_targets_reject_semantically_incompatible_profile_fields(target: TargetAI, mode: str) -> None:
    built = PromptBuilder().build(
        PromptGenerateRequest(input=SMOKE_INPUT, category="imagem", mode=mode, target_ai=target,
                              **INCOMPATIBLE_PROFILE_FIELDS)
    )
    assert SMOKE_INPUT in built
    assert "## ENVIRONMENT" in built
    assert "mesa de madeira" in built
    assert "pizzaria elegante" in built
    assert "## COMPOSITION" in built
    assert "## VISUAL STYLE" in built
    if target == TargetAI.MIDJOURNEY:
        assert "## MOOD\nElegante" in built
    details_heading = "RELEVANT DETAILS" if target == TargetAI.MIDJOURNEY else "IMPORTANT DETAILS"
    assert f"## {details_heading}" in built
    assert built.count("## ") == len(set(re.findall(r"(?m)^## ([^\n]+)$", built)))
    for incompatible in INCOMPATIBLE_PROFILE_FIELDS.values():
        for value in incompatible if isinstance(incompatible, list) else [incompatible]:
            assert value not in built


@pytest.mark.parametrize("target", [TargetAI.VIDEO_GENERATOR, TargetAI.CODING_ASSISTANT])
def test_specialized_targets_do_not_relabel_unrelated_business_fields(target: TargetAI) -> None:
    built = PromptBuilder().build(
        PromptGenerateRequest(input=SMOKE_INPUT, mode="expert", target_ai=target,
                              **INCOMPATIBLE_PROFILE_FIELDS)
    )
    assert SMOKE_INPUT in built
    for incompatible in INCOMPATIBLE_PROFILE_FIELDS.values():
        for value in incompatible if isinstance(incompatible, list) else [incompatible]:
            assert value not in built


def test_video_target_extracts_explicit_duration_action_and_environment() -> None:
    built = PromptBuilder().build(
        PromptGenerateRequest(
            input=(
                "Criar um vídeo publicitário de 15 segundos mostrando uma pizza artesanal sendo servida "
                "em uma pizzaria elegante."
            ),
            target_ai=TargetAI.VIDEO_GENERATOR,
            mode="basic",
            **INCOMPATIBLE_PROFILE_FIELDS,
        )
    )
    assert "## SUBJECT\numa pizza artesanal" in built
    assert "## ACTION\nsendo servida" in built
    assert "## ENVIRONMENT\numa pizzaria elegante" in built
    assert "## TEMPORAL CONTEXT\n15 segundos" in built
    assert built.count("## ") == len(set(re.findall(r"(?m)^## ([^\n]+)$", built)))


def test_video_smoke_separates_scene_subject_and_complete_action_sequence() -> None:
    request = (
        "Criar um vídeo publicitário de 15 segundos mostrando uma pizza artesanal italiana sendo preparada, "
        "saindo do forno e sendo servida em uma mesa de madeira em uma pizzaria elegante."
    )
    built = PromptBuilder().build(
        PromptGenerateRequest(
            input=request,
            category="video",
            mode="basic",
            target_ai=TargetAI.VIDEO_GENERATOR,
            **INCOMPATIBLE_PROFILE_FIELDS,
        )
    )
    assert "## SCENE" in built
    assert "## SUBJECT\numa pizza artesanal italiana" in built
    assert "sendo preparada; saindo do forno; sendo servida" in built
    assert "## ENVIRONMENT\numa mesa de madeira; uma pizzaria elegante" in built
    assert "## TEMPORAL CONTEXT\n15 segundos" in built
    sections = PromptService._structured_sections(built)
    assert sections["SCENE"] != sections["SUBJECT"]
    assert sections["SCENE"] != request
    for incompatible in INCOMPATIBLE_PROFILE_FIELDS.values():
        for value in incompatible if isinstance(incompatible, list) else [incompatible]:
            assert value not in built


@pytest.mark.parametrize(
    ("prompt_text", "subject", "actions"),
    [
        (
            "Crie um vídeo de 20 segundos mostrando um tênis sendo retirado da caixa, colocado nos pés "
            "e usado durante uma caminhada em uma rua de Paris.",
            "um tênis",
            ("sendo retirado da caixa", "colocado nos pés", "usado durante uma caminhada"),
        ),
        (
            "Crie um vídeo de 10 segundos mostrando um café sendo preparado, servido em uma xícara "
            "e colocado sobre uma mesa.",
            "um café",
            ("sendo preparado", "servido em uma xícara", "colocado sobre uma mesa"),
        ),
    ],
)
def test_video_action_sequence_is_generic(prompt_text: str, subject: str, actions: tuple[str, ...]) -> None:
    built = PromptBuilder().build(
        PromptGenerateRequest(input=prompt_text, target_ai=TargetAI.VIDEO_GENERATOR)
    )
    assert f"## SUBJECT\n{subject}" in built
    assert all(action in built for action in actions)


def test_coding_target_extracts_stack_and_keeps_explicit_requirement() -> None:
    request = "Criar uma API REST em Python com FastAPI para cadastro de produtos."
    built = PromptBuilder().build(
        PromptGenerateRequest(
            input=request,
            target_ai=TargetAI.CODING_ASSISTANT,
            mode="basic",
            **INCOMPATIBLE_PROFILE_FIELDS,
        )
    )
    assert "## STACK\nPython, FastAPI" in built
    assert f"## REQUIREMENTS\n{request}" in built
    assert built.count("## ") == len(set(re.findall(r"(?m)^## ([^\n]+)$", built)))


@pytest.mark.parametrize("target", [TargetAI.GENERIC, TargetAI.CHATGPT, TargetAI.CLAUDE, TargetAI.GEMINI])
def test_general_targets_preserve_compatible_general_fields(target: TargetAI) -> None:
    built = PromptBuilder().build(
        PromptGenerateRequest(input=SMOKE_INPUT, mode="pro", target_ai=target, **INCOMPATIBLE_PROFILE_FIELDS)
    )
    assert INCOMPATIBLE_PROFILE_FIELDS["context"] in built
    assert INCOMPATIBLE_PROFILE_FIELDS["audience"] in built
    assert INCOMPATIBLE_PROFILE_FIELDS["output_format"] in built


def test_missing_target_ai_defaults_to_generic_and_invalid_target_is_rejected() -> None:
    assert PromptGenerateRequest(input="Crie algo útil").target_ai == TargetAI.GENERIC
    with pytest.raises(ValueError):
        PromptGenerateRequest(input="Crie algo útil", target_ai="unknown")


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
            text=(
                "## ROLE\nEspecialista\n\n## OBJECTIVE\nCrie uma campanha\n\n"
                "## INSTRUCTIONS\nProduza uma resposta clara.\n\n## LANGUAGE\npt-BR"
            ),
            latency_ms=1,
            usage=TokenUsageResponse(input_tokens=10, output_tokens=4, total_tokens=14),
        )


class ParaphrasingGateway:
    async def generate(self, _data: object) -> GenerateTextResponse:
        return GenerateTextResponse(
            provider="fake",
            model="test-model",
            text=(
                "## ROLE\nEspecialista em marketing digital\n\n"
                "## OBJECTIVE\nProduza uma peça publicitária breve para promover a oferta "
                "de uma pizzaria no Instagram.\n\n"
                "## INSTRUCTIONS\nDestaque a promoção com uma chamada clara e persuasiva.\n\n"
                "## LANGUAGE\npt-BR"
            ),
            latency_ms=1,
            usage=TokenUsageResponse(input_tokens=40, output_tokens=55, total_tokens=95),
        )


class ResolvingGateway:
    async def generate(self, data: GenerateTextRequest) -> GenerateTextResponse:
        requested_model = data.model
        return GenerateTextResponse(
            provider="openai",
            model=requested_model or "gpt-5.6-luna",
            text=(
                "## ROLE\nEspecialista\n\n## OBJECTIVE\nCrie uma campanha\n\n"
                "## INSTRUCTIONS\nProduza uma resposta clara.\n\n## LANGUAGE\npt-BR"
            ),
            latency_ms=1,
            usage=TokenUsageResponse(input_tokens=10, output_tokens=4, total_tokens=14),
        )


class CapturingBilling:
    def __init__(self) -> None:
        self.repository = self
        self.finalized_model: str | None = None

    async def reserve_ai_generation(self, _user_id: object, _provider: str) -> SimpleNamespace:
        return SimpleNamespace()

    async def finalize_usage(self, _record: object, **values: object) -> None:
        self.finalized_model = values["model"]  # type: ignore[assignment]


class CapturingCredits:
    def __init__(self) -> None:
        self.settled_provider: str | None = None
        self.settled_model: str | None = None

    async def estimate(self, *_args: object) -> None:
        return None

    async def reserve(self, *_args: object) -> SimpleNamespace:
        return SimpleNamespace(id=uuid4())

    async def settle(
        self,
        _reservation_id: object,
        _provider: str,
        _model: str | None,
        _input_tokens: int,
        _output_tokens: int,
        *,
        effective_provider: str | None = None,
        effective_model: str | None = None,
    ) -> None:
        self.settled_provider = effective_provider
        self.settled_model = effective_model


@pytest.mark.asyncio
@pytest.mark.parametrize("mode", list(PromptMode))
async def test_service_optimizes_only_through_injected_gateway(mode: PromptMode) -> None:
    service = PromptService(SimpleNamespace(), FakeGateway())
    saved: dict[str, object] = {}

    async def fake_create(**values: object) -> SimpleNamespace:
        saved.update(values)
        now = __import__("datetime").datetime.now(__import__("datetime").UTC)
        return SimpleNamespace(id=uuid4(), created_at=now, updated_at=now, **values)

    service.repository.create = fake_create
    service.repository.get_by_idempotency_key = lambda *_: _none()

    async def fake_update(prompt: SimpleNamespace, **values: object) -> SimpleNamespace:
        for field, value in values.items():
            setattr(prompt, field, value)
        return prompt

    service.repository.update = fake_update
    user = SimpleNamespace(id=uuid4(), role=Role.USER)
    response = await service.generate(
        user, PromptGenerateRequest(input="Crie uma campanha", optimize_with_ai=True, mode=mode)
    )

    assert "## OBJECTIVE\nCrie uma campanha" in response.generated_prompt
    assert response.status == PromptStatus.OPTIMIZED
    assert response.provider == "fake"
    assert response.usage is not None and response.usage.total_tokens == 14
    assert response.total_tokens == 14
    assert saved["category"] == PromptCategory.GENERAL


async def _none() -> None:
    return None


@pytest.mark.asyncio
async def test_basic_marketing_accepts_semantically_preserved_paraphrase() -> None:
    service = PromptService(SimpleNamespace(), ParaphrasingGateway())

    async def fake_create(**values: object) -> SimpleNamespace:
        now = __import__("datetime").datetime.now(__import__("datetime").UTC)
        return SimpleNamespace(id=uuid4(), created_at=now, updated_at=now, **values)

    async def fake_update(prompt: SimpleNamespace, **values: object) -> SimpleNamespace:
        for field, value in values.items():
            setattr(prompt, field, value)
        return prompt

    service.repository.create = fake_create
    service.repository.update = fake_update
    service.repository.get_by_idempotency_key = lambda *_: _none()

    response = await service.generate(
        SimpleNamespace(id=uuid4(), role=Role.USER),
        PromptGenerateRequest(
            input="Crie um anúncio curto para uma pizzaria divulgar uma promoção de pizza no Instagram.",
            category="marketing",
            mode="basic",
            optimize_with_ai=True,
        ),
    )

    assert response.status == PromptStatus.OPTIMIZED
    assert "pizzaria" in response.generated_prompt
    assert "Instagram" in response.generated_prompt


@pytest.mark.asyncio
@pytest.mark.parametrize("requested_model", [None, "explicit-model"])
async def test_settlement_uses_effective_gateway_model(requested_model: str | None) -> None:
    billing = CapturingBilling()
    credits = CapturingCredits()
    service = PromptService(SimpleNamespace(), ResolvingGateway(), billing, credits)

    async def fake_create(**values: object) -> SimpleNamespace:
        now = __import__("datetime").datetime.now(__import__("datetime").UTC)
        return SimpleNamespace(id=uuid4(), created_at=now, updated_at=now, **values)

    async def fake_update(prompt: SimpleNamespace, **values: object) -> SimpleNamespace:
        for field, value in values.items():
            setattr(prompt, field, value)
        return prompt

    service.repository.create = fake_create
    service.repository.update = fake_update
    service.repository.get_by_idempotency_key = lambda *_: _none()

    response = await service.generate(
        SimpleNamespace(id=uuid4(), role=Role.USER),
        PromptGenerateRequest(
            input="Crie uma campanha",
            optimize_with_ai=True,
            provider="openai",
            model=requested_model,
        ),
    )

    expected_model = requested_model or "gpt-5.6-luna"
    assert response.model == expected_model
    assert billing.finalized_model == expected_model
    assert credits.settled_provider == "openai"
    assert credits.settled_model == expected_model


@pytest.mark.parametrize("value", ["", "  ", "resposta sem o requisito"])
def test_ai_output_validation_rejects_empty_or_missing_requirements(
    value: str, caplog: pytest.LogCaptureFixture
) -> None:
    with caplog.at_level("WARNING"), pytest.raises(Exception) as error:
        PromptService._validated_output(
            value,
            PromptGenerateRequest(
                input="Crie uma campanha",
                constraints=["Não invente dados"],
            ),
        )
    assert getattr(error.value, "status_code", None) == 502
    assert "ai_output_rejected stage=output_validation" in caplog.text
    assert "Crie uma campanha" not in caplog.text
    assert "NÃ£o invente dados" not in caplog.text
