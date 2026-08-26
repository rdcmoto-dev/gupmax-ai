from datetime import datetime
from enum import StrEnum
from uuid import UUID, uuid4

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.modules.prompt_engine.enums import PromptCategory, PromptMode, TargetAI


class PromptChainStatus(StrEnum):
    ACTIVE = "active"
    ARCHIVED = "archived"


class PromptChain(Base):
    __tablename__ = "prompt_chains"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    project_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("projects.id", ondelete="SET NULL"), index=True
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(String(1000))
    status: Mapped[PromptChainStatus] = mapped_column(
        String(20), default=PromptChainStatus.ACTIVE, nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class PromptChainStep(Base):
    __tablename__ = "prompt_chain_steps"
    __table_args__ = (UniqueConstraint("chain_id", "position", name="uq_chain_step_position"),)

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    chain_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("prompt_chains.id", ondelete="CASCADE"), nullable=False, index=True
    )
    template_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("prompt_templates.id", ondelete="SET NULL"), index=True
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    base_input: Mapped[str] = mapped_column(Text, nullable=False)
    mode: Mapped[PromptMode] = mapped_column(String(20), nullable=False)
    category: Mapped[PromptCategory] = mapped_column(String(40), nullable=False)
    target_ai: Mapped[TargetAI] = mapped_column(String(40), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
