from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class SmartProfileWrite(BaseModel):
    is_enabled: bool = True
    default_language: str | None = Field(default=None, max_length=20)
    default_tone: str | None = Field(default=None, max_length=80)
    default_audience: str | None = Field(default=None, max_length=1000)
    default_channel: str | None = Field(default=None, max_length=200)
    default_output_format: str | None = Field(default=None, max_length=1000)
    business_context: str | None = Field(default=None, max_length=4000)
    default_constraints: list[str] = Field(default_factory=list, max_length=30)
    default_instructions: list[str] = Field(default_factory=list, max_length=30)

    @field_validator(
        "default_language",
        "default_tone",
        "default_audience",
        "default_channel",
        "default_output_format",
        "business_context",
    )
    @classmethod
    def normalize_optional(cls, value: str | None) -> str | None:
        normalized = value.strip() if value is not None else None
        return normalized or None

    @field_validator("default_constraints", "default_instructions")
    @classmethod
    def normalize_lines(cls, values: list[str]) -> list[str]:
        normalized = [value.strip() for value in values if value.strip()]
        if any(len(value) > 500 for value in normalized):
            raise ValueError("items must contain at most 500 characters")
        return normalized


class SmartProfileRead(SmartProfileWrite):
    model_config = ConfigDict(from_attributes=True)

    id: UUID | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
