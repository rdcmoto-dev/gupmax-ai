from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import DateTime, ForeignKey, Numeric, String, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.modules.payments.enums import EventProcessingStatus, PaymentProviderName, PaymentPurpose, PaymentStatus


class Payment(Base):
    __tablename__ = "payments"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    provider: Mapped[PaymentProviderName] = mapped_column(String(30), nullable=False)
    purpose: Mapped[PaymentPurpose] = mapped_column(String(30), nullable=False)
    status: Mapped[PaymentStatus] = mapped_column(String(20), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    credit_package_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), ForeignKey("credit_packages.id"))
    plan_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), ForeignKey("plans.id"))
    provider_payment_id: Mapped[str | None] = mapped_column(String(255), index=True)
    provider_checkout_id: Mapped[str | None] = mapped_column(String(255), index=True)
    checkout_url: Mapped[str | None] = mapped_column(String(2048))
    idempotency_key: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    canceled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    user: Mapped[User] = relationship(back_populates="payments")


class PaymentEvent(Base):
    __tablename__ = "payment_events"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    provider: Mapped[PaymentProviderName] = mapped_column(String(30), nullable=False)
    provider_event_id: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    event_type: Mapped[str] = mapped_column(String(100), nullable=False)
    payload_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    processing_status: Mapped[EventProcessingStatus] = mapped_column(String(20), nullable=False)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
    processed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    error_message: Mapped[str | None] = mapped_column(String(500))


from app.modules.users.model import User  # noqa: E402, F401
