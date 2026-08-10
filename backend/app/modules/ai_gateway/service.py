import logging
from collections.abc import AsyncIterator

from app.core.ai_exceptions import AIConfigurationError
from app.modules.ai_gateway.contracts import (
    GenerationInput,
    GenerationOutput,
    GenerationStreamEvent,
    TextGenerationProvider,
)
from app.modules.ai_gateway.schemas import (
    GenerateTextRequest,
    GenerateTextResponse,
    ProviderListResponse,
    ProviderResponse,
)

logger = logging.getLogger(__name__)


class AIGatewayService:
    def __init__(self, providers: dict[str, TextGenerationProvider]) -> None:
        self._providers = providers

    def list_providers(self) -> ProviderListResponse:
        providers = [
            ProviderResponse(provider=provider.name, models=provider.available_models())
            for provider in self._providers.values()
            if provider.is_available
        ]
        return ProviderListResponse(providers=providers)

    def _provider(self, provider_name: str) -> TextGenerationProvider:
        provider = self._providers.get(provider_name)
        if provider is None or not provider.is_available:
            raise AIConfigurationError()
        return provider

    @staticmethod
    def _input(data: GenerateTextRequest) -> GenerationInput:
        return GenerationInput(
            model=data.model,
            system_prompt=data.system_prompt,
            user_prompt=data.user_prompt,
            temperature=data.temperature,
            max_output_tokens=data.max_output_tokens,
        )

    @staticmethod
    def _response(output: GenerationOutput) -> GenerateTextResponse:
        return GenerateTextResponse(
            provider=output.provider,
            model=output.model,
            text=output.text,
            latency_ms=output.latency_ms,
            usage=output.usage,
        )

    @staticmethod
    def _log(output: GenerationOutput) -> None:
        logger.info(
            "ai_generation_completed",
            extra={
                "provider": output.provider,
                "model": output.model,
                "latency_ms": output.latency_ms,
                "input_tokens": output.usage.input_tokens,
                "output_tokens": output.usage.output_tokens,
                "total_tokens": output.usage.total_tokens,
            },
        )

    async def generate(self, data: GenerateTextRequest) -> GenerateTextResponse:
        output = await self._provider(data.provider).generate(self._input(data))
        self._log(output)
        return self._response(output)

    async def stream(self, data: GenerateTextRequest) -> AsyncIterator[GenerationStreamEvent]:
        async for event in self._provider(data.provider).stream(self._input(data)):
            if event.output is not None:
                self._log(event.output)
            yield event
