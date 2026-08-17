from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.modules.prompt_engine.enums import PromptCategory, PromptMode, PromptStatus


class Prompt(Base):
    __tablename__ = "prompts"
    __table_args__ = (UniqueConstraint("user_id", "idempotency_key", name="uq_prompts_user_idempotency_key"),)

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    original_input: Mapped[str] = mapped_column(Text, nullable=False)
    generated_prompt: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[PromptCategory] = mapped_column(String(40), nullable=False, index=True)
    language: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    tone: Mapped[str | None] = mapped_column(String(80))
    mode: Mapped[PromptMode] = mapped_column(String(20), nullable=False, index=True)
    status: Mapped[PromptStatus] = mapped_column(String(20), nullable=False)
    provider: Mapped[str | None] = mapped_column(String(50))
    model: Mapped[str | None] = mapped_column(String(200))
    input_tokens: Mapped[int | None] = mapped_column(Integer)
    output_tokens: Mapped[int | None] = mapped_column(Integer)
    total_tokens: Mapped[int | None] = mapped_column(Integer)
    idempotency_key: Mapped[str | None] = mapped_column(String(200), index=True)
    request_fingerprint: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    user: Mapped[User] = relationship(back_populates="prompts")


from app.modules.users.model import User  # noqa: E402, F401
