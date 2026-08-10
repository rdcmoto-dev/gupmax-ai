from functools import lru_cache
from typing import Annotated

from fastapi import Depends

from app.core.config import get_settings
from app.modules.ai_gateway.openai_provider import OpenAIProvider
from app.modules.ai_gateway.service import AIGatewayService


@lru_cache
def get_ai_gateway_service() -> AIGatewayService:
    settings = get_settings()
    api_key = settings.openai_api_key.get_secret_value() if settings.openai_api_key is not None else None
    provider = OpenAIProvider(
        api_key=api_key,
        default_model=settings.openai_default_model,
        models=settings.openai_models,
        timeout_seconds=settings.openai_timeout_seconds,
        max_retries=settings.openai_max_retries,
    )
    return AIGatewayService({provider.name: provider})


AIGateway = Annotated[AIGatewayService, Depends(get_ai_gateway_service)]
