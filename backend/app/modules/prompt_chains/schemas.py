from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, computed_field, field_validator

from app.modules.prompt_chains.model import PromptChainStatus
from app.modules.prompt_engine.enums import PromptCategory, PromptMode, TargetAI
from app.modules.prompt_templates.schemas import TemplateVariable
from app.modules.prompt_templates.variables import detect_variables, variable_label

RESERVED_PREVIOUS_RESULT = "resultado_anterior"


class ChainCreate(BaseModel):
    name: str = Field(min_length=3, max_length=200)
    description: str | None = Field(default=None, max_length=1000)
    project_id: UUID | None = None

    @field_validator("name", "description")
    @classmethod
    def normalize(cls, value: str | None) -> str | None:
        value = value.strip() if value is not None else None
        return value or None


class ChainUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=3, max_length=200)
    description: str | None = Field(default=None, max_length=1000)
    project_id: UUID | None = None
    status: PromptChainStatus | None = None


class StepFields(BaseModel):
    title: str = Field(min_length=3, max_length=200)
    base_input: str = Field(min_length=3, max_length=10_000)
    mode: PromptMode = PromptMode.BASIC
    category: PromptCategory = PromptCategory.GENERAL
    target_ai: TargetAI = TargetAI.GENERIC
    template_id: UUID | None = None

    @field_validator("title", "base_input")
    @classmethod
    def normalize(cls, value: str) -> str:
        return value.strip()


class StepCreate(StepFields):
    pass


class StepUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=3, max_length=200)
    base_input: str | None = Field(default=None, min_length=3, max_length=10_000)
    mode: PromptMode | None = None
    category: PromptCategory | None = None
    target_ai: TargetAI | None = None
    template_id: UUID | None = None


class ReorderSteps(BaseModel):
    step_ids: list[UUID] = Field(min_length=1, max_length=20)


class StepRead(StepFields):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    chain_id: UUID
    position: int
    created_at: datetime
    updated_at: datetime

    @computed_field
    @property
    def variables(self) -> list[TemplateVariable]:
        return [
            TemplateVariable(name=name, label=variable_label(name))
            for name in detect_variables(self.base_input)
            if name != RESERVED_PREVIOUS_RESULT
        ]

    @computed_field
    @property
    def requires_previous_result(self) -> bool:
        return RESERVED_PREVIOUS_RESULT in detect_variables(self.base_input)


class ChainRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    project_id: UUID | None
    name: str
    description: str | None
    status: PromptChainStatus
    step_count: int = 0
    created_at: datetime
    updated_at: datetime


class ChainDetail(ChainRead):
    steps: list[StepRead]


class ChainPage(BaseModel):
    items: list[ChainRead]
    total: int
    offset: int
    limit: int
