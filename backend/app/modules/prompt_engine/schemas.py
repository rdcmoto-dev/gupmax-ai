from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.modules.ai_gateway.schemas import TokenUsageResponse
from app.modules.prompt_engine.enums import PromptCategory, PromptMode, PromptStatus


class PromptGenerateRequest(BaseModel):
    input: str = Field(min_length=3, max_length=10_000)
    category: PromptCategory = PromptCategory.GENERAL
    language: str = Field(default="pt-BR", min_length=2, max_length=20, pattern=r"^[A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?$")
    tone: str | None = Field(default=None, min_length=2, max_length=80)
    mode: PromptMode = PromptMode.BASIC
    optimize_with_ai: bool = False
    title: str | None = Field(default=None, min_length=3, max_length=160)
    context: str | None = Field(default=None, max_length=4_000)
    audience: str | None = Field(default=None, max_length=1_000)
    role: str | None = Field(default=None, max_length=500)
    instructions: list[str] = Field(default_factory=list, max_length=30)
    constraints: list[str] = Field(default_factory=list, max_length=30)
    output_format: str | None = Field(default=None, max_length=1_000)
    additional_information: str | None = Field(default=None, max_length=2_000)
    provider: str = Field(default="openai", min_length=1, max_length=50)
    model: str | None = Field(default=None, min_length=1, max_length=200)

    @field_validator("input", "title", "context", "audience", "role", "tone", "output_format", "additional_information")
    @classmethod
    def reject_blank(cls, value: str | None) -> str | None:
        if value is not None and not value.strip():
            raise ValueError("must not be blank")
        return value.strip() if value is not None else None

    @field_validator("instructions", "constraints")
    @classmethod
    def validate_items(cls, values: list[str]) -> list[str]:
        if any(not item.strip() or len(item) > 500 for item in values):
            raise ValueError("items must contain 1 to 500 characters")
        return [item.strip() for item in values]


class PromptUpdateRequest(BaseModel):
    title: str | None = Field(default=None, min_length=3, max_length=160)
    generated_prompt: str | None = Field(default=None, min_length=3, max_length=30_000)
    category: PromptCategory | None = None
    language: str | None = Field(default=None, min_length=2, max_length=20)
    tone: str | None = Field(default=None, min_length=2, max_length=80)
    mode: PromptMode | None = None


class PromptRefineRequest(BaseModel):
    instruction: str = Field(min_length=3, max_length=1000)
    optimize_with_ai: bool = False
    provider: str = Field(default="openai", min_length=1, max_length=50)
    model: str | None = Field(default=None, min_length=1, max_length=200)

    @field_validator("instruction")
    @classmethod
    def normalize_instruction(cls, value: str) -> str:
        normalized = " ".join(value.split())
        if not normalized:
            raise ValueError("must not be blank")
        return normalized


class PromptRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    title: str
    original_input: str
    generated_prompt: str
    category: PromptCategory
    language: str
    tone: str | None
    mode: PromptMode
    status: PromptStatus
    provider: str | None
    model: str | None
    input_tokens: int | None
    output_tokens: int | None
    total_tokens: int | None
    parent_prompt_id: UUID | None
    root_prompt_id: UUID | None
    version_number: int
    refinement_instruction: str | None
    created_at: datetime
    updated_at: datetime


class PromptGenerateResponse(PromptRead):
    usage: TokenUsageResponse | None = None


class PromptPage(BaseModel):
    items: list[PromptRead]
    total: int
    offset: int
    limit: int


class PromptVersionPage(BaseModel):
    items: list[PromptRead]
    total: int
