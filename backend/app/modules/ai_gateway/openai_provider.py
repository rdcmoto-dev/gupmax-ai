import logging
from collections.abc import AsyncIterator
from dataclasses import dataclass
from time import perf_counter

import openai
from openai import AsyncOpenAI

from app.core.ai_exceptions import AIConfigurationError, AIRequestError, AIUnavailableError
from app.core.config import get_settings
from app.modules.ai_gateway.contracts import GenerationInput, GenerationOutput, GenerationStreamEvent, TokenUsage

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ModelCapabilities:
    supports_temperature: bool = True


MODEL_CAPABILITIES = {
    "gpt-5.6-luna": ModelCapabilities(supports_temperature=False),
}


class OpenAIProvider:
    name = "openai"

    def __init__(
        self,
        api_key: str | None,
        default_model: str | None,
        models: list[str],
        timeout_seconds: float,
        max_retries: int,
    ) -> None:
        self._default_model = default_model
        self._models = models
        self._client = (
            AsyncOpenAI(api_key=api_key, timeout=timeout_seconds, max_retries=max_retries)
            if api_key is not None
            else None
        )

    @property
    def is_available(self) -> bool:
        return self._client is not None

    def available_models(self) -> list[str]:
        return self._models.copy()

    def _model_for(self, requested_model: str | None) -> str:
        model = requested_model or self._default_model
        if model is None:
            raise AIConfigurationError()
        if self._models and model not in self._models:
            raise AIRequestError()
        return model

    @staticmethod
    def _capabilities(model: str) -> ModelCapabilities:
        return MODEL_CAPABILITIES.get(model, ModelCapabilities())

    @staticmethod
    def _usage(response: object) -> TokenUsage:
        usage = getattr(response, "usage", None)
        return TokenUsage(
            input_tokens=getattr(usage, "input_tokens", None),
            output_tokens=getattr(usage, "output_tokens", None),
            total_tokens=getattr(usage, "total_tokens", None),
        )

    @staticmethod
    def _raise_mapped(error: Exception) -> None:
        if isinstance(error, openai.BadRequestError):
            if get_settings().environment.lower() in {"development", "test"}:
                body = error.body if isinstance(error.body, dict) else {}
                logger.warning(
                    "openai_bad_request status=%s type=%s code=%s param=%s message=%s",
                    error.status_code,
                    body.get("type"),
                    body.get("code"),
                    body.get("param"),
                    body.get("message"),
                    extra={
                        "provider_status": error.status_code,
                        "error_type": body.get("type"),
                        "error_code": body.get("code"),
                        "error_param": body.get("param"),
                        "error_message": body.get("message"),
                    },
                )
            raise AIRequestError() from error
        if isinstance(error, (openai.AuthenticationError, openai.PermissionDeniedError)):
            raise AIConfigurationError() from error
        if isinstance(
            error,
            (openai.APIConnectionError, openai.APITimeoutError, openai.RateLimitError, openai.InternalServerError),
        ):
            raise AIUnavailableError() from error
        if isinstance(error, openai.APIStatusError):
            raise AIUnavailableError() from error
        raise AIUnavailableError() from error

    async def generate(self, generation_input: GenerationInput) -> GenerationOutput:
        if self._client is None:
            raise AIConfigurationError()
        model = self._model_for(generation_input.model)
        started_at = perf_counter()
        try:
            response = await self._create_response(generation_input, model)
        except Exception as error:
            self._raise_mapped(error)
            raise AIUnavailableError() from error
        return GenerationOutput(
            provider=self.name,
            model=response.model,
            text=response.output_text,
            latency_ms=round((perf_counter() - started_at) * 1000),
            usage=self._usage(response),
        )

    async def validate_model(self, model: str) -> str:
        if self._client is None:
            raise AIConfigurationError()
        try:
            retrieved_model = await self._client.models.retrieve(model)
        except Exception as error:
            self._raise_mapped(error)
            raise AIUnavailableError() from error
        return retrieved_model.id

    async def stream(self, generation_input: GenerationInput) -> AsyncIterator[GenerationStreamEvent]:
        if self._client is None:
            raise AIConfigurationError()
        model = self._model_for(generation_input.model)
        started_at = perf_counter()
        try:
            stream = await self._create_response(generation_input, model, stream=True)
            async for event in stream:
                if event.type == "response.output_text.delta":
                    yield GenerationStreamEvent(event="token", text=event.delta)
                if event.type == "response.completed":
                    response = event.response
                    yield GenerationStreamEvent(
                        event="complete",
                        output=GenerationOutput(
                            provider=self.name,
                            model=response.model,
                            text=response.output_text,
                            latency_ms=round((perf_counter() - started_at) * 1000),
                            usage=self._usage(response),
                        ),
                    )
        except Exception as error:
            self._raise_mapped(error)
            raise AIUnavailableError() from error

    async def _create_response(self, generation_input: GenerationInput, model: str, stream: bool = False) -> object:
        if self._client is None:
            raise AIConfigurationError()
        arguments: dict[str, object] = {
            "model": model,
            "input": generation_input.user_prompt,
            "instructions": generation_input.system_prompt,
            "max_output_tokens": generation_input.max_output_tokens,
            "stream": stream,
        }
        if generation_input.temperature is not None and self._capabilities(model).supports_temperature:
            arguments["temperature"] = generation_input.temperature
        return await self._client.responses.create(**arguments)  # type: ignore[arg-type]
