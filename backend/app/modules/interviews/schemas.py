from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.modules.interviews.enums import InterviewStatus, QuestionType
from app.modules.prompt_engine.enums import PromptCategory, PromptMode
from app.modules.prompt_engine.schemas import PromptGenerateRequest


class InterviewCreateRequest(BaseModel):
    initial_request: str = Field(min_length=3, max_length=10_000)
    mode: PromptMode
    category: PromptCategory = PromptCategory.GENERAL

    @field_validator("initial_request")
    @classmethod
    def normalize_request(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("must not be blank")
        return value.strip()


class InterviewQuestion(BaseModel):
    key: str = Field(pattern=r"^[a-z][a-z0-9_]{1,63}$")
    text: str = Field(min_length=3, max_length=500)
    type: QuestionType
    required: bool = True
    options: list[str] = Field(default_factory=list, max_length=20)

    @field_validator("options")
    @classmethod
    def validate_options(cls, options: list[str]) -> list[str]:
        if len(options) != len(set(options)) or any(not option.strip() or len(option) > 100 for option in options):
            raise ValueError("options must be unique and contain 1 to 100 characters")
        return options


AnswerValue = str | bool | list[str]


class InterviewAnswerInput(BaseModel):
    question_key: str = Field(pattern=r"^[a-z][a-z0-9_]{1,63}$")
    value: AnswerValue


class InterviewAnswersRequest(BaseModel):
    answers: list[InterviewAnswerInput] = Field(min_length=1, max_length=50)

    @field_validator("answers")
    @classmethod
    def unique_keys(cls, answers: list[InterviewAnswerInput]) -> list[InterviewAnswerInput]:
        keys = [answer.question_key for answer in answers]
        if len(keys) != len(set(keys)):
            raise ValueError("question keys must be unique")
        return answers


class InterviewAnswerRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    question_key: str
    value: Any
    created_at: datetime
    updated_at: datetime


class InterviewProgress(BaseModel):
    answered: int
    total: int
    required_answered: int
    required_total: int


class InterviewRead(BaseModel):
    id: UUID
    user_id: UUID
    status: InterviewStatus
    mode: PromptMode
    category: PromptCategory
    initial_request: str
    questions: list[InterviewQuestion]
    answers: list[InterviewAnswerRead]
    progress: InterviewProgress
    structured_prompt: PromptGenerateRequest | None = None
    created_at: datetime
    updated_at: datetime
    completed_at: datetime | None
    expires_at: datetime


class InterviewCompleteResponse(BaseModel):
    interview: InterviewRead
    prompt_input: PromptGenerateRequest
