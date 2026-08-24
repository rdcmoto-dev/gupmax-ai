from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.modules.projects.model import ProjectStatus
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
