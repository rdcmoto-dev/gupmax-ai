from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator

from app.modules.prompt_chains.schemas import ChainDetail, StepCreate
from app.modules.prompt_engine.enums import PromptCategory, PromptMode, TargetAI
from app.modules.prompt_engine.schemas import SMART_ANSWER_KEYS


class ExpertPlanRequest(BaseModel):
    input: str = Field(min_length=3, max_length=10_000)
    project_id: UUID | None = None
    category: PromptCategory = PromptCategory.GENERAL
    mode: PromptMode = PromptMode.EXPERT
    target_ai: TargetAI = TargetAI.GENERIC
    smart_answers: dict[str, str] = Field(default_factory=dict, max_length=5)

    @field_validator("input")
    @classmethod
    def normalize_input(cls, value: str) -> str:
        return value.strip()

    @field_validator("smart_answers")
    @classmethod
    def validate_answers(cls, values: dict[str, str]) -> dict[str, str]:
        result: dict[str, str] = {}
        for key, value in values.items():
            if key not in SMART_ANSWER_KEYS:
                raise ValueError("unsupported smart answer key")
            clean = value.strip()
            if clean:
                if len(clean) > 1_000:
                    raise ValueError("smart answer is too long")
                result[key] = clean
        return result


class ExpertPlanStep(BaseModel):
    position: int = Field(ge=1, le=20)
    title: str = Field(min_length=3, max_length=200)
    objective: str = Field(min_length=3, max_length=2_000)
    base_input: str = Field(min_length=3, max_length=10_000)
    category: PromptCategory
    mode: PromptMode = PromptMode.EXPERT
    target_ai: TargetAI = TargetAI.GENERIC
    requires_previous_result: bool = False


class ExpertPlan(BaseModel):
    summary: str
    suggested_name: str = Field(min_length=3, max_length=200)
    planning_recommended: bool
    plan_type: str
    steps: list[ExpertPlanStep] = Field(min_length=2, max_length=10)


class CreateChainFromPlan(BaseModel):
    name: str = Field(min_length=3, max_length=200)
    description: str | None = Field(default=None, max_length=1_000)
    project_id: UUID | None = None
    steps: list[StepCreate] = Field(min_length=1, max_length=20)

    @field_validator("name", "description")
    @classmethod
    def normalize_text(cls, value: str | None) -> str | None:
        return value.strip() if value is not None else None

    @model_validator(mode="after")
    def valid_steps(self) -> CreateChainFromPlan:
        if any(not step.title.strip() or not step.base_input.strip() for step in self.steps):
            raise ValueError("invalid step")
        return self


class CreatedPlanChain(BaseModel):
    chain: ChainDetail
