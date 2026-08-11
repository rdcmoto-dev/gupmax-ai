from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Numeric, String, Text, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.modules.billing.enums import BillingInterval, PaymentProvider, SubscriptionStatus


class Plan(Base):
    __tablename__ = "plans"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    code: Mapped[str] = mapped_column(String(40), unique=True, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    billing_interval: Mapped[BillingInterval] = mapped_column(String(20), nullable=False)
    trial_days: Mapped[int] = mapped_column(Integer, nullable=False)
    monthly_generation_limit: Mapped[int] = mapped_column(Integer, nullable=False)
    monthly_input_token_limit: Mapped[int] = mapped_column(Integer, nullable=False)
    monthly_output_token_limit: Mapped[int] = mapped_column(Integer, nullable=False)
    monthly_credit_grant: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    subscriptions: Mapped[list[Subscription]] = relationship(back_populates="plan")


class Subscription(Base):
    __tablename__ = "subscriptions"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True, nullable=False
    )
    plan_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("plans.id"), index=True, nullable=False)
    status: Mapped[SubscriptionStatus] = mapped_column(String(20), nullable=False)
    provider: Mapped[PaymentProvider] = mapped_column(String(30), nullable=False)
    provider_customer_id: Mapped[str | None] = mapped_column(String(255))
    provider_subscription_id: Mapped[str | None] = mapped_column(String(255))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    current_period_start: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    current_period_end: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    cancel_at_period_end: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    canceled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    trial_started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    trial_ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    user: Mapped[User] = relationship(back_populates="subscription")
    plan: Mapped[Plan] = relationship(back_populates="subscriptions")


class UsageRecord(Base):
    __tablename__ = "usage_records"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    prompt_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("prompts.id", ondelete="SET NULL"), index=True
    )
    provider: Mapped[str] = mapped_column(String(50), nullable=False)
    model: Mapped[str | None] = mapped_column(String(200))
    input_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    total_tokens: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    generation_count: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True, nullable=False
    )
    user: Mapped[User] = relationship(back_populates="usage_records")
    prompt: Mapped[Prompt | None] = relationship()


from app.modules.prompt_engine.model import Prompt  # noqa: E402, F401
from app.modules.users.model import User  # noqa: E402, F401
