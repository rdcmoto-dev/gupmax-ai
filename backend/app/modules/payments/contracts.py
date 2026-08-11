from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from typing import Protocol

from app.modules.payments.enums import PaymentProviderName, PaymentStatus


@dataclass(frozen=True)
class CheckoutInput:
    internal_payment_id: str
    idempotency_key: str
    title: str
    amount: Decimal
    currency: str
    customer_email: str
    success_url: str
    cancel_url: str
    webhook_url: str
    recurring: bool = False
    interval: str | None = None


@dataclass(frozen=True)
class CheckoutOutput:
    checkout_id: str
    checkout_url: str
    payment_id: str | None = None


@dataclass(frozen=True)
class WebhookNotification:
    event_id: str
    event_type: str
    resource_id: str


@dataclass(frozen=True)
class ProviderPayment:
    payment_id: str
    checkout_id: str | None
    status: PaymentStatus
    amount: Decimal
    currency: str
    customer_id: str | None = None
    subscription_id: str | None = None
    period_start: datetime | None = None
    period_end: datetime | None = None
    internal_payment_id: str | None = None


class PaymentProvider(Protocol):
    name: PaymentProviderName

    async def create_checkout(self, data: CheckoutInput) -> CheckoutOutput: ...

    def verify_webhook(self, payload: bytes, headers: dict[str, str], query: dict[str, str]) -> WebhookNotification: ...

    async def get_payment(self, resource_id: str) -> ProviderPayment: ...

    async def cancel_subscription(self, subscription_id: str) -> None: ...
