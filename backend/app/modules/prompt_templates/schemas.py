from datetime import datetime
from typing import Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, computed_field, field_validator, model_validator

from app.modules.prompt_engine.enums import PromptCategory, PromptMode, TargetAI
from app.modules.prompt_templates.variables import detect_variables, validate_variable_count, variable_label


class TemplateVariable(BaseModel):
    name: str
    label: str
    required: bool = True


class TemplateFields(BaseModel):
    category: PromptCategory = PromptCategory.GENERAL
    mode: PromptMode = PromptMode.BASIC
    target_ai: TargetAI = TargetAI.GENERIC
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

    @model_validator(mode="after")
    def validate_variables(self) -> Self:
        validate_variable_count(
            detect_variables(
                self.template_content,
                self.base_input,
                self.tone,
                self.audience,
                self.context,
                self.output_format,
                self.additional_information,
                *self.instructions,
                *self.constraints,
            )
        )
        return self


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
    target_ai: TargetAI | None = None
    template_content: str | None = Field(default=None, min_length=3, max_length=30_000)
    base_input: str | None = Field(default=None, min_length=3, max_length=10_000)
    is_active: bool | None = None


class TemplateRead(TemplateFields):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    project_id: UUID | None
    source_prompt_id: UUID | None
    name: str
    description: str | None
    created_at: datetime
    updated_at: datetime

    @computed_field
    @property
    def variables(self) -> list[TemplateVariable]:
        names = detect_variables(
            self.template_content,
            self.base_input,
            self.tone,
            self.audience,
            self.context,
            self.output_format,
            self.additional_information,
            *self.instructions,
            *self.constraints,
        )
        return [TemplateVariable(name=name, label=variable_label(name)) for name in names]

    @computed_field
    @property
    def has_variables(self) -> bool:
        return bool(self.variables)


class TemplatePage(BaseModel):
    items: list[TemplateRead]
    total: int
    offset: int
    limit: int
