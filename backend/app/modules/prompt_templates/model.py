from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, String, Text, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.modules.prompt_engine.enums import PromptCategory, PromptMode, TargetAI


class PromptTemplate(Base):
    __tablename__ = "prompt_templates"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    project_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("projects.id", ondelete="SET NULL"), index=True
    )
    source_prompt_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("prompts.id", ondelete="SET NULL"), index=True
    )
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    description: Mapped[str | None] = mapped_column(String(1000))
    category: Mapped[PromptCategory] = mapped_column(String(40), nullable=False, index=True)
    mode: Mapped[PromptMode] = mapped_column(String(20), nullable=False, index=True)
    target_ai: Mapped[TargetAI] = mapped_column(String(40), nullable=False, default=TargetAI.GENERIC, index=True)
    template_content: Mapped[str] = mapped_column(Text, nullable=False)
    base_input: Mapped[str] = mapped_column(Text, nullable=False)
    language: Mapped[str] = mapped_column(String(20), nullable=False, default="pt-BR")
    tone: Mapped[str | None] = mapped_column(String(80))
    audience: Mapped[str | None] = mapped_column(String(1000))
    context: Mapped[str | None] = mapped_column(Text)
    output_format: Mapped[str | None] = mapped_column(String(1000))
    constraints: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    instructions: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    additional_information: Mapped[str | None] = mapped_column(String(2000))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
