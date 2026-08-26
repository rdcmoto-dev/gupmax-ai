from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.modules.prompt_engine.enums import PromptCategory, PromptMode, TargetAI


class IntentAnalyzeRequest(BaseModel):
    input: str = Field(min_length=3, max_length=10_000)
    category: PromptCategory | None = None
    mode: PromptMode = PromptMode.BASIC
    target_ai: TargetAI = TargetAI.GENERIC
    project_id: UUID | None = None
    template_id: UUID | None = None

    @field_validator("input")
    @classmethod
    def normalize_input(cls, value: str) -> str:
        value = " ".join(value.split())
        if len(value) < 3:
            raise ValueError("input is too short")
        return value


class IntentQuestion(BaseModel):
    model_config = ConfigDict(frozen=True)

    key: str
    label: str


class IntentAnalysis(BaseModel):
    summary: str
    intent: str
    suggested_category: PromptCategory
    detected_entities: dict[str, str]
    missing_information: list[str]
    suggested_questions: list[IntentQuestion]
    confidence: float = Field(ge=0, le=1)
