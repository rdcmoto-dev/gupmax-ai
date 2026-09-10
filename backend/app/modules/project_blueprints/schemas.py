from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.modules.prompt_engine.enums import PromptCategory, PromptMode, TargetAI

Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=3, max_length=160)]
Description = Annotated[str, StringConstraints(strip_whitespace=True, max_length=1000)]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", from_attributes=True)


class BlueprintCreate(StrictModel):
    source_project_id: UUID
    name: Name
    description: Description | None = None


class BlueprintUpdate(StrictModel):
    name: Name
    description: Description | None = None
    category: PromptCategory


class BlueprintUse(StrictModel):
    name: Name


class BlueprintStep(StrictModel):
    title: str = Field(min_length=3, max_length=200)
    base_input: str = Field(min_length=3, max_length=10_000)
    mode: PromptMode
    category: PromptCategory
    target_ai: TargetAI


class BlueprintChain(StrictModel):
    name: str = Field(min_length=3, max_length=200)
    description: Description | None = None
    steps: list[BlueprintStep] = Field(max_length=20)


class BlueprintStructure(StrictModel):
    version: int = Field(default=1, ge=1, le=1)
    project_name: Name
    description: Description | None = None
    objective: str | None = Field(default=None, max_length=1000)
    success_criteria: list[Annotated[str, Field(max_length=1000)]] = Field(default_factory=list, max_length=5)
    milestones: list[Annotated[str, Field(max_length=500)]] = Field(default_factory=list, max_length=5)
    context: str | None = Field(default=None, max_length=4000)
    chains: list[BlueprintChain] = Field(max_length=100)


class BlueprintRead(StrictModel):
    id: UUID
    name: str
    description: str | None
    category: PromptCategory
    created_at: datetime
    updated_at: datetime


class BlueprintDetail(BlueprintRead):
    structure: BlueprintStructure


class BlueprintPage(StrictModel):
    items: list[BlueprintRead]
    total: int
    offset: int
    limit: int
