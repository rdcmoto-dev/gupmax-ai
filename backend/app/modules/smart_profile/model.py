from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, String, Text, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class UserPromptPreferences(Base):
    __tablename__ = "user_prompt_preferences"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False, index=True
    )
    is_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    default_language: Mapped[str | None] = mapped_column(String(20))
    default_tone: Mapped[str | None] = mapped_column(String(80))
    default_audience: Mapped[str | None] = mapped_column(String(1000))
    default_channel: Mapped[str | None] = mapped_column(String(200))
    default_output_format: Mapped[str | None] = mapped_column(String(1000))
    business_context: Mapped[str | None] = mapped_column(Text)
    default_constraints: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    default_instructions: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
