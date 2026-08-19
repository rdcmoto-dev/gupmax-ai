from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.modules.prompt_engine.enums import PromptCategory, PromptMode


class TemplateFields(BaseModel):
    category: PromptCategory = PromptCategory.GENERAL
    mode: PromptMode = PromptMode.BASIC
    template_content: str = Field(min_length=3, max_length=30_000)
    base_input: str = Field(min_length=3, max_length=10_000)
    language: str = Field(default="pt-BR", min_length=2, max_length=20)
    tone: str | None = Field(default=None, max_length=80)
    audience: str | None = Field(default=None, max_length=1000)
    context: str | None = Field(default=None, max_length=4000)
    output_format: str | None = Field(default=None, max_length=1000)
    constraints: list[str] = Field(default_factory=list, max_length=30)
    instructions: list[str] = Field(default_factory=list, max_length=30)
    additional_information: str | None = Field(default=None, max_length=2000)
    is_active: bool = True

    @field_validator(
        "template_content", "base_input", "tone", "audience", "context", "output_format", "additional_information"
    )
    @classmethod
    def normalize_text(cls, value: str | None) -> str | None:
        normalized = value.strip() if value is not None else None
        return normalized or None

    @field_validator("constraints", "instructions")
    @classmethod
    def normalize_lists(cls, values: list[str]) -> list[str]:
        normalized = [value.strip() for value in values if value.strip()]
        if any(len(value) > 500 for value in normalized):
            raise ValueError("items must contain at most 500 characters")
        return normalized


class TemplateCreate(TemplateFields):
    name: str = Field(min_length=3, max_length=160)
    description: str | None = Field(default=None, max_length=1000)

    @field_validator("name", "description")
    @classmethod
    def normalize_identity(cls, value: str | None) -> str | None:
        normalized = " ".join(value.split()) if value is not None else None
        return normalized or None


class TemplateFromPrompt(BaseModel):
    name: str = Field(min_length=3, max_length=160)
    description: str | None = Field(default=None, max_length=1000)

    @field_validator("name", "description")
    @classmethod
    def normalize_identity(cls, value: str | None) -> str | None:
        normalized = " ".join(value.split()) if value is not None else None
        return normalized or None


class TemplateUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=3, max_length=160)
    description: str | None = Field(default=None, max_length=1000)
    category: PromptCategory | None = None
    mode: PromptMode | None = None
    template_content: str | None = Field(default=None, min_length=3, max_length=30_000)
    base_input: str | None = Field(default=None, min_length=3, max_length=10_000)
    is_active: bool | None = None


class TemplateRead(TemplateFields):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    source_prompt_id: UUID | None
    name: str
    description: str | None
    created_at: datetime
    updated_at: datetime


class TemplatePage(BaseModel):
    items: list[TemplateRead]
    total: int
    offset: int
    limit: int
