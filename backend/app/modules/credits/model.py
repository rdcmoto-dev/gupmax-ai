from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import JSON, BigInteger, Boolean, DateTime, ForeignKey, Integer, Numeric, String, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.modules.credits.enums import CreditOperationType, CreditSource, CreditTransactionType, ReservationStatus


class CreditWallet(Base):
    __tablename__ = "credit_wallets"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )
    available_balance: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    reserved_balance: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    lifetime_credited: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    lifetime_spent: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    user: Mapped[User] = relationship(back_populates="credit_wallet")
    lots: Mapped[list[CreditLot]] = relationship(back_populates="wallet", cascade="all, delete-orphan")
    transactions: Mapped[list[CreditTransaction]] = relationship(back_populates="wallet", cascade="all, delete-orphan")
    reservations: Mapped[list[CreditReservation]] = relationship(back_populates="wallet", cascade="all, delete-orphan")


class CreditLot(Base):
    __tablename__ = "credit_lots"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    wallet_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("credit_wallets.id", ondelete="CASCADE"), index=True
    )
    source: Mapped[CreditSource] = mapped_column(String(20), nullable=False)
    original_amount: Mapped[int] = mapped_column(BigInteger, nullable=False)
    available_amount: Mapped[int] = mapped_column(BigInteger, nullable=False)
    reserved_amount: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    wallet: Mapped[CreditWallet] = relationship(back_populates="lots")


class CreditTransaction(Base):
    __tablename__ = "credit_transactions"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    wallet_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("credit_wallets.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    type: Mapped[CreditTransactionType] = mapped_column(String(30), nullable=False)
    amount: Mapped[int] = mapped_column(BigInteger, nullable=False)
    balance_after: Mapped[int] = mapped_column(BigInteger, nullable=False)
    reference_type: Mapped[str] = mapped_column(String(50), nullable=False)
    reference_id: Mapped[str] = mapped_column(String(255), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    description: Mapped[str] = mapped_column(String(500), nullable=False)
    transaction_metadata: Mapped[dict[str, object] | None] = mapped_column("metadata", JSON)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
    wallet: Mapped[CreditWallet] = relationship(back_populates="transactions")


class CreditReservation(Base):
    __tablename__ = "credit_reservations"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    wallet_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("credit_wallets.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    operation_type: Mapped[CreditOperationType] = mapped_column(String(40), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    reserved_credits: Mapped[int] = mapped_column(BigInteger, nullable=False)
    settled_credits: Mapped[int | None] = mapped_column(BigInteger)
    status: Mapped[ReservationStatus] = mapped_column(String(20), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    settled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    wallet: Mapped[CreditWallet] = relationship(back_populates="reservations")
    allocations: Mapped[list[CreditReservationAllocation]] = relationship(cascade="all, delete-orphan")


class CreditReservationAllocation(Base):
    __tablename__ = "credit_reservation_allocations"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    reservation_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("credit_reservations.id", ondelete="CASCADE"), index=True
    )
    lot_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey("credit_lots.id"), index=True)
    amount: Mapped[int] = mapped_column(BigInteger, nullable=False)
    lot: Mapped[CreditLot] = relationship()


class CreditPackage(Base):
    __tablename__ = "credit_packages"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    code: Mapped[str] = mapped_column(String(50), unique=True, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    credits: Mapped[int] = mapped_column(BigInteger, nullable=False)
    price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    bonus_credits: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class CreditCostRule(Base):
    __tablename__ = "credit_cost_rules"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    operation_type: Mapped[CreditOperationType] = mapped_column(String(40), index=True, nullable=False)
    provider: Mapped[str] = mapped_column(String(50), nullable=False)
    model: Mapped[str | None] = mapped_column(String(200))
    base_credit_cost: Mapped[int] = mapped_column(Integer, nullable=False)
    input_token_rate: Mapped[Decimal] = mapped_column(Numeric(12, 6), nullable=False)
    output_token_rate: Mapped[Decimal] = mapped_column(Numeric(12, 6), nullable=False)
    minimum_credit_cost: Mapped[int] = mapped_column(Integer, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


from app.modules.users.model import User  # noqa: E402, F401
