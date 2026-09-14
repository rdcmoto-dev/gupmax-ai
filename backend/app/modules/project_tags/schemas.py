from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class TagInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=1, max_length=60)

    @field_validator("name")
    @classmethod
    def trim(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Nome da etiqueta é obrigatório.")
        return v


class TagRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    user_id: UUID
    name: str
    created_at: datetime
    updated_at: datetime
