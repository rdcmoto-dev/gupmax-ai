from functools import lru_cache
from typing import Annotated

from pydantic import BeforeValidator, Field, PostgresDsn, SecretStr
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


def _parse_origins(value: str | list[str]) -> list[str]:
    if isinstance(value, list):
        return value
    return [origin.strip() for origin in value.split(",") if origin.strip()]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_ignore_empty=True, extra="ignore")

    app_name: str = "GUPMAX AI"
    app_version: str = "0.1.0"
    environment: str = "development"
    debug: bool = Field(default=False, validation_alias="GUPMAX_DEBUG")
    api_v1_prefix: str = "/api/v1"
    docs_enabled: bool = True
    database_url: PostgresDsn
    redis_url: str = "redis://localhost:6379/0"
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 7
    password_reset_token_expire_minutes: int = 30
    openai_api_key: SecretStr | None = None
    openai_default_model: str | None = None
    openai_models: Annotated[list[str], NoDecode, BeforeValidator(_parse_origins)] = []
    openai_timeout_seconds: float = Field(default=30.0, gt=0, le=300)
    openai_max_retries: int = Field(default=2, ge=0, le=5)
    cors_origins: Annotated[list[str], NoDecode, BeforeValidator(_parse_origins)] = ["http://localhost:3000"]


@lru_cache
def get_settings() -> Settings:
    return Settings()
