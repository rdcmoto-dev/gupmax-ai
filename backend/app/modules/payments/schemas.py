from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.modules.payments.enums import PaymentProviderName, PaymentPurpose, PaymentStatus


class CreditCheckoutRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    package_id: UUID
    provider: PaymentProviderName


class SubscriptionCheckoutRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    plan_id: UUID
    provider: PaymentProviderName


class CheckoutResponse(BaseModel):
    payment_id: UUID
    provider: PaymentProviderName
    checkout_url: str
    status: PaymentStatus


class PaymentRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    provider: PaymentProviderName
    purpose: PaymentPurpose
    status: PaymentStatus
    amount: Decimal
    currency: str
    credit_package_id: UUID | None
    plan_id: UUID | None
    created_at: datetime
    updated_at: datetime
    paid_at: datetime | None
    canceled_at: datetime | None
    failed_at: datetime | None


class PaymentPage(BaseModel):
    items: list[PaymentRead]
    total: int
    offset: int
    limit: int


class CancelSubscriptionResponse(BaseModel):
    cancel_at_period_end: bool
