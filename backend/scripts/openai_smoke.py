"""Manual low-cost OpenAI smoke test; execute only with configured OpenAI credentials."""

import asyncio

from app.core.config import get_settings
from app.modules.ai_gateway.contracts import GenerationInput
from app.modules.ai_gateway.openai_provider import OpenAIProvider


async def main() -> None:
    settings = get_settings()
    if settings.openai_api_key is None or settings.openai_default_model is None:
        print("Smoke test skipped: OPENAI_API_KEY and OPENAI_DEFAULT_MODEL must be configured.")
        return

    provider = OpenAIProvider(
        api_key=settings.openai_api_key.get_secret_value(),
        default_model=settings.openai_default_model,
        models=settings.openai_models,
        timeout_seconds=settings.openai_timeout_seconds,
        max_retries=settings.openai_max_retries,
    )
    model = await provider.validate_model(settings.openai_default_model)
    output = await provider.generate(
        GenerationInput(
            model=model,
            system_prompt="Reply concisely.",
            user_prompt="Reply with OK.",
            temperature=None,
            max_output_tokens=16,
        )
    )
    print(
        "Smoke test passed: "
        f"model={output.model}, input_tokens={output.usage.input_tokens}, "
        f"output_tokens={output.usage.output_tokens}, total_tokens={output.usage.total_tokens}"
    )


if __name__ == "__main__":
    asyncio.run(main())
