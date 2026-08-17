from types import SimpleNamespace

import httpx
import openai
import pytest

from app.core.ai_exceptions import AIConfigurationError, AIRequestError
from app.modules.ai_gateway.contracts import GenerationInput, GenerationOutput, TokenUsage
from app.modules.ai_gateway.openai_provider import OpenAIProvider
from app.modules.ai_gateway.schemas import GenerateTextRequest
from app.modules.ai_gateway.service import AIGatewayService


def test_gateway_returns_no_provider_when_openai_is_not_configured() -> None:
    provider = OpenAIProvider(
        api_key=None,
        default_model=None,
        models=[],
        timeout_seconds=30.0,
        max_retries=2,
    )
    gateway = AIGatewayService({provider.name: provider})

    assert gateway.list_providers().providers == []


class TypedUsageProvider:
    name = "typed"
    is_available = True

    def available_models(self) -> list[str]:
        return ["typed-model"]

    async def generate(self, _input: GenerationInput) -> GenerationOutput:
        return GenerationOutput(
            provider=self.name,
            model="typed-model",
            text="Prompt otimizado",
            latency_ms=1,
            usage=TokenUsage(input_tokens=12, output_tokens=5, total_tokens=17),
        )


@pytest.mark.asyncio
async def test_gateway_serializes_typed_token_usage_at_response_boundary() -> None:
    gateway = AIGatewayService({"typed": TypedUsageProvider()})

    response = await gateway.generate(GenerateTextRequest(provider="typed", user_prompt="Prompt original"))

    assert response.usage.model_dump() == {
        "input_tokens": 12,
        "output_tokens": 5,
        "total_tokens": 17,
    }
    assert '"usage":{"input_tokens":12,"output_tokens":5,"total_tokens":17}' in response.model_dump_json()


@pytest.mark.asyncio
async def test_gateway_rejects_generation_without_an_available_provider() -> None:
    gateway = AIGatewayService({})
    request = GenerateTextRequest(user_prompt="Olá")

    with pytest.raises(AIConfigurationError):
        await gateway.generate(request)


@pytest.mark.asyncio
async def test_openai_provider_omits_unsupported_temperature_for_luna() -> None:
    provider = OpenAIProvider(
        api_key="test-key",
        default_model="gpt-5.6-luna",
        models=[],
        timeout_seconds=30,
        max_retries=0,
    )
    captured: dict[str, object] = {}

    async def create(**kwargs: object) -> object:
        captured.update(kwargs)
        return SimpleNamespace(
            model="gpt-5.6-luna",
            output_text="Prompt otimizado",
            usage=SimpleNamespace(input_tokens=10, output_tokens=5, total_tokens=15),
        )

    provider._client = SimpleNamespace(responses=SimpleNamespace(create=create))
    await provider.generate(
        GenerationInput(
            model=None,
            system_prompt="Otimize o prompt.",
            user_prompt="Prompt original",
            temperature=0.2,
            max_output_tokens=2_000,
        )
    )

    assert captured == {
        "model": "gpt-5.6-luna",
        "input": "Prompt original",
        "instructions": "Otimize o prompt.",
        "max_output_tokens": 2_000,
        "stream": False,
    }
    assert not ({"messages", "max_tokens", "top_p", "reasoning", "text", "metadata"} & captured.keys())


@pytest.mark.asyncio
async def test_openai_provider_preserves_temperature_for_models_without_override() -> None:
    provider = OpenAIProvider(
        api_key="test-key",
        default_model="temperature-capable-model",
        models=[],
        timeout_seconds=30,
        max_retries=0,
    )
    captured: dict[str, object] = {}

    async def create(**kwargs: object) -> object:
        captured.update(kwargs)
        return SimpleNamespace(
            model="temperature-capable-model",
            output_text="Prompt otimizado",
            usage=SimpleNamespace(input_tokens=10, output_tokens=5, total_tokens=15),
        )

    provider._client = SimpleNamespace(responses=SimpleNamespace(create=create))
    await provider.generate(
        GenerationInput(
            model=None,
            system_prompt="Otimize o prompt.",
            user_prompt="Prompt original",
            temperature=0.2,
            max_output_tokens=2_000,
        )
    )

    assert captured["temperature"] == 0.2


def test_openai_bad_request_logs_only_safe_upstream_fields(caplog: pytest.LogCaptureFixture) -> None:
    request = httpx.Request("POST", "https://api.openai.com/v1/responses")
    response = httpx.Response(400, request=request)
    error = openai.BadRequestError(
        "provider rejected parameter",
        response=response,
        body={
            "type": "invalid_request_error",
            "code": "unsupported_value",
            "param": "temperature",
            "message": "Unsupported value for temperature",
        },
    )

    with caplog.at_level("WARNING"), pytest.raises(AIRequestError):
        OpenAIProvider._raise_mapped(error)

    record = next(item for item in caplog.records if item.msg.startswith("openai_bad_request"))
    assert record.provider_status == 400
    assert record.error_type == "invalid_request_error"
    assert record.error_code == "unsupported_value"
    assert record.error_param == "temperature"
    assert record.error_message == "Unsupported value for temperature"
    assert "param=temperature" in record.getMessage()
    assert "Authorization" not in caplog.text
    assert "test-key" not in caplog.text
