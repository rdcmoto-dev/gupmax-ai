import asyncio
from unittest.mock import MagicMock

import pytest
from pydantic import PostgresDsn, ValidationError

from app.core.config import Settings
from app.core.exceptions import DomainError
from app.core.features import require_external_features_enabled
from app.modules.ai_gateway import dependencies as ai_dependencies
from app.modules.ai_gateway.router import generate_text, stream_text
from app.modules.ai_gateway.schemas import GenerateTextRequest
from app.modules.prompt_engine.router import generate_prompt, refine_prompt
from app.modules.prompt_engine.schemas import PromptGenerateRequest, PromptRefineRequest


def settings(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "_env_file": None,
        "database_url": PostgresDsn("postgresql+asyncpg://user:password@db:5432/app"),
        "jwt_secret_key": "pilot-test-secret-that-is-at-least-32-characters-long",
        "pilot_mode": True,
    }
    values.update(overrides)
    return Settings(**values)


def test_pilot_mode_rejects_external_credentials() -> None:
    with pytest.raises(ValidationError, match="PILOT_MODE"):
        settings(openai_api_key="test-key")


def test_pilot_mode_blocks_paid_features_before_side_effects(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("app.core.features.get_settings", lambda: settings())

    with pytest.raises(DomainError, match="disabled in pilot"):
        require_external_features_enabled()


def test_pilot_mode_exposes_no_ai_provider(monkeypatch: pytest.MonkeyPatch) -> None:
    ai_dependencies.get_ai_gateway_service.cache_clear()
    monkeypatch.setattr(ai_dependencies, "get_settings", lambda: settings())

    gateway = ai_dependencies.get_ai_gateway_service()

    assert gateway.list_providers().providers == []
    ai_dependencies.get_ai_gateway_service.cache_clear()


def test_pilot_mode_rejects_direct_ai_generation_before_side_effects(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("app.core.features.get_settings", lambda: settings())
    gateway = MagicMock()
    billing = MagicMock()
    credits = MagicMock()
    data = GenerateTextRequest(user_prompt="Generate a prompt")

    with pytest.raises(DomainError, match="External AI features"):
        asyncio.run(generate_text(data, gateway, billing, credits, MagicMock()))

    gateway.generate.assert_not_called()
    billing.reserve_ai_generation.assert_not_called()
    billing.repository.finalize_usage.assert_not_called()
    credits.reserve.assert_not_called()
    credits.settle.assert_not_called()


def test_pilot_mode_rejects_streaming_ai_generation_before_side_effects(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("app.core.features.get_settings", lambda: settings())
    gateway = MagicMock()
    billing = MagicMock()
    credits = MagicMock()
    data = GenerateTextRequest(user_prompt="Generate a prompt")

    with pytest.raises(DomainError, match="External AI features"):
        asyncio.run(stream_text(data, gateway, billing, credits, MagicMock()))

    gateway.stream.assert_not_called()
    billing.reserve_ai_generation.assert_not_called()
    credits.reserve.assert_not_called()


def test_pilot_mode_rejects_prompt_ai_paths_before_side_effects(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("app.core.features.get_settings", lambda: settings())
    gateway = MagicMock()
    billing = MagicMock()
    credits = MagicMock()
    user = MagicMock()
    generate_data = PromptGenerateRequest(input="Write a launch announcement", optimize_with_ai=True)
    refine_data = PromptRefineRequest(instruction="Make it more concise", optimize_with_ai=True)

    with pytest.raises(DomainError, match="External AI features"):
        asyncio.run(generate_prompt(generate_data, MagicMock(), user, gateway, billing, credits))
    with pytest.raises(DomainError, match="External AI features"):
        asyncio.run(refine_prompt(MagicMock(), refine_data, MagicMock(), user, gateway, billing, credits))

    gateway.generate.assert_not_called()
    billing.reserve_ai_generation.assert_not_called()
    billing.repository.finalize_usage.assert_not_called()
    credits.estimate.assert_not_called()
    credits.reserve.assert_not_called()
    credits.settle.assert_not_called()
