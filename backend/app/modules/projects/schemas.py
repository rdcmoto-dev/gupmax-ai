from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.modules.projects.model import ProjectStatus
from app.modules.prompt_chains.model import PromptChainStepStatus
from app.modules.prompt_engine.enums import PromptCategory, PromptMode, TargetAI
from app.modules.prompt_engine.schemas import PromptRead
from app.modules.prompt_templates.schemas import TemplateRead


class ProjectCreate(BaseModel):
    name: str = Field(min_length=3, max_length=160)
    description: str | None = Field(default=None, max_length=1000)
    context: str | None = Field(default=None, max_length=4000)

    @field_validator("name", "description", "context")
    @classmethod
    def normalize(cls, value: str | None) -> str | None:
        normalized = value.strip() if value is not None else None
        return normalized or None


class ProjectUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=3, max_length=160)
    description: str | None = Field(default=None, max_length=1000)
    context: str | None = Field(default=None, max_length=4000)
    status: ProjectStatus | None = None

    @field_validator("name", "description", "context")
    @classmethod
    def normalize(cls, value: str | None) -> str | None:
        normalized = value.strip() if value is not None else None
        return normalized or None


class ProjectRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    name: str
    description: str | None
    context: str | None
    status: ProjectStatus
    prompt_count: int = 0
    template_count: int = 0
    created_at: datetime
    updated_at: datetime


class ProjectPage(BaseModel):
    items: list[ProjectRead]
    total: int
    offset: int
    limit: int


class ProjectDetail(ProjectRead):
    prompts: list[PromptRead]
    templates: list[TemplateRead]


class ProjectLibraryPrompt(BaseModel):
    id: UUID
    title: str
    category: PromptCategory
    mode: PromptMode
    target_ai: TargetAI
    version_count: int
    created_at: datetime
    updated_at: datetime


class ProjectLibraryStep(BaseModel):
    id: UUID
    position: int
    title: str
    status: PromptChainStepStatus
    has_result: bool
    result_preview: str | None = None
    completed_at: datetime | None = None


class ProjectLibraryChain(BaseModel):
    id: UUID
    name: str
    completed_count: int
    step_count: int
    current_step_id: UUID | None
    steps: list[ProjectLibraryStep]
    updated_at: datetime


class ProjectActivityItem(BaseModel):
    kind: str
    label: str
    occurred_at: datetime
    stable_id: UUID


class ProjectLibraryPage(BaseModel):
    project_id: UUID
    prompts: list[ProjectLibraryPrompt]
    prompt_total: int
    offset: int
    limit: int
    chains: list[ProjectLibraryChain]
    completed_step_count: int
    activity: list[ProjectActivityItem]
    last_activity_at: datetime
