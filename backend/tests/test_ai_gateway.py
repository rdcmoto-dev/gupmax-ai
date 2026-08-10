import pytest

from app.core.ai_exceptions import AIConfigurationError
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


@pytest.mark.asyncio
async def test_gateway_rejects_generation_without_an_available_provider() -> None:
    gateway = AIGatewayService({})
    request = GenerateTextRequest(user_prompt="Olá")

    with pytest.raises(AIConfigurationError):
        await gateway.generate(request)
