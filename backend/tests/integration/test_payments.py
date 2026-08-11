import asyncio
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.main import app
from app.modules.billing.model import Subscription
from app.modules.credits.model import CreditPackage, CreditTransaction, CreditWallet
from app.modules.payments.contracts import CheckoutInput, CheckoutOutput, ProviderPayment, WebhookNotification
from app.modules.payments.dependencies import PaymentProviderRegistry, get_payment_provider_registry
from app.modules.payments.enums import PaymentProviderName, PaymentStatus
from app.modules.payments.exceptions import InvalidWebhook, PaymentProviderError
from app.modules.payments.model import Payment, PaymentEvent
from app.modules.users.model import User
from app.modules.users.roles import Role


class FakeProvider:
    def __init__(self, name: PaymentProviderName) -> None:
        self.name = name
        self.checkouts: list[CheckoutInput] = []
        self.remotes: dict[str, ProviderPayment] = {}
        self.canceled: list[str] = []
        self.fail_checkout = False

    async def create_checkout(self, data: CheckoutInput) -> CheckoutOutput:
        if self.fail_checkout:
            raise PaymentProviderError()
        self.checkouts.append(data)
        return CheckoutOutput(
            checkout_id=f"checkout-{len(self.checkouts)}",
            checkout_url=f"https://sandbox.example/{self.name.value}/{len(self.checkouts)}",
        )

    def verify_webhook(
        self, payload: bytes, headers: dict[str, str], query: dict[str, str]
    ) -> WebhookNotification:
        del query
        if headers.get("x-fake-signature") != "valid":
            raise InvalidWebhook()
        event_id, event_type, resource_id = payload.decode().split(":", 2)
        return WebhookNotification(event_id, event_type, resource_id)

    async def get_payment(self, resource_id: str) -> ProviderPayment:
        return self.remotes[resource_id]

    async def cancel_subscription(self, subscription_id: str) -> None:
        self.canceled.append(subscription_id)


@pytest.fixture
def providers() -> tuple[FakeProvider, FakeProvider]:
    stripe = FakeProvider(PaymentProviderName.STRIPE)
    mercado_pago = FakeProvider(PaymentProviderName.MERCADO_PAGO)
    app.dependency_overrides[get_payment_provider_registry] = lambda: PaymentProviderRegistry(
        {stripe.name: stripe, mercado_pago.name: mercado_pago}
    )
    yield stripe, mercado_pago
    app.dependency_overrides.pop(get_payment_provider_registry, None)


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Payment User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def package_id(client: TestClient, headers: dict[str, str]) -> str:
    return client.get("/api/v1/credits/packages", headers=headers).json()[0]["id"]


def plan_id(client: TestClient, headers: dict[str, str]) -> str:
    return client.get("/api/v1/billing/plans", headers=headers).json()[1]["id"]


def checkout_credit(
    client: TestClient,
    headers: dict[str, str],
    package: str,
    provider: str = "stripe",
    key: str = "checkout-key-001",
):
    return client.post(
        "/api/v1/payments/credits/checkout",
        headers={**headers, "Idempotency-Key": key},
        json={"package_id": package, "provider": provider},
    )


def webhook(client: TestClient, provider: str, payload: str, valid: bool = True):
    return client.post(
        f"/api/v1/payments/webhooks/{provider}",
        headers={"x-fake-signature": "valid" if valid else "forged"},
        content=payload,
    )


@pytest.mark.parametrize("provider_index", [0, 1])
def test_credit_checkout_uses_database_price_and_is_idempotent(
    client: TestClient,
    providers: tuple[FakeProvider, FakeProvider],
    provider_index: int,
    session_factory: async_sessionmaker[AsyncSession],
) -> None:
    headers = auth(client, f"checkout-{provider_index}@example.com")
    package = package_id(client, headers)
    provider = providers[provider_index]
    first = checkout_credit(client, headers, package, provider.name.value, f"idempotent-{provider_index}")
    second = checkout_credit(client, headers, package, provider.name.value, f"idempotent-{provider_index}")
    assert first.status_code == 201, first.text
    assert second.json()["payment_id"] == first.json()["payment_id"]
    assert len(provider.checkouts) == 1

    async def values() -> tuple[Decimal, str]:
        async with session_factory() as session:
            payment = await session.get(Payment, UUID(first.json()["payment_id"]))
            credit_package = await session.get(CreditPackage, UUID(package))
            return payment.amount, credit_package.currency

    amount, currency = asyncio.run(values())
    assert provider.checkouts[0].amount == amount
    assert provider.checkouts[0].currency == currency


def test_checkout_authentication_missing_products_and_timeout(
    client: TestClient, providers: tuple[FakeProvider, FakeProvider]
) -> None:
    missing = "10000000-0000-0000-0000-000000000099"
    assert checkout_credit(client, {}, missing).status_code == 401
    headers = auth(client, "missing-product@example.com")
    assert checkout_credit(client, headers, missing).status_code == 404
    assert (
        client.post(
            "/api/v1/payments/subscriptions/checkout",
            headers={**headers, "Idempotency-Key": "missing-plan-key"},
            json={"plan_id": missing, "provider": "stripe"},
        ).status_code
        == 404
    )
    package = package_id(client, headers)
    manipulated = client.post(
        "/api/v1/payments/credits/checkout",
        headers={**headers, "Idempotency-Key": "manipulated-key"},
        json={"package_id": package, "provider": "stripe", "amount": "0.01", "credits": 999999},
    )
    assert manipulated.status_code == 422
    providers[0].fail_checkout = True
    assert checkout_credit(client, headers, package, key="timeout-key-001").status_code == 502


def test_valid_webhook_grants_purchase_once_and_rejects_forgery(
    client: TestClient,
    providers: tuple[FakeProvider, FakeProvider],
    session_factory: async_sessionmaker[AsyncSession],
) -> None:
    stripe = providers[0]
    headers = auth(client, "paid@example.com")
    package = package_id(client, headers)
    checkout = checkout_credit(client, headers, package)
    payment_id = checkout.json()["payment_id"]
    stripe.remotes["resource-paid"] = ProviderPayment(
        payment_id="provider-payment-1",
        checkout_id="checkout-1",
        status=PaymentStatus.PAID,
        amount=stripe.checkouts[0].amount,
        currency=stripe.checkouts[0].currency,
        internal_payment_id=payment_id,
    )
    assert webhook(client, "stripe", "evt-forged:paid:resource-paid", False).status_code == 400
    assert webhook(client, "stripe", "evt-paid:paid:resource-paid").status_code == 204
    assert webhook(client, "stripe", "evt-paid:paid:resource-paid").status_code == 204

    async def assert_state() -> tuple[int, int, PaymentStatus, int]:
        async with session_factory() as session:
            payment = await session.get(Payment, UUID(payment_id))
            user = await session.get(User, payment.user_id)
            wallet = await session.scalar(select(CreditWallet).where(CreditWallet.user_id == user.id))
            purchase_count = await session.scalar(
                select(func.count())
                .select_from(CreditTransaction)
                .where(CreditTransaction.idempotency_key == "purchase:stripe:provider-payment-1")
            )
            event_count = await session.scalar(select(func.count()).select_from(PaymentEvent))
            return wallet.available_balance, purchase_count, payment.status, event_count

    balance, purchase_count, payment_status, event_count = asyncio.run(assert_state())
    assert balance > 100
    assert purchase_count == 1
    assert payment_status == PaymentStatus.PAID
    assert event_count == 1


@pytest.mark.parametrize("mismatch", ["amount", "currency"])
def test_confirmation_mismatch_does_not_credit(
    client: TestClient,
    providers: tuple[FakeProvider, FakeProvider],
    session_factory: async_sessionmaker[AsyncSession],
    mismatch: str,
) -> None:
    stripe = providers[0]
    headers = auth(client, f"mismatch-{mismatch}@example.com")
    checkout = checkout_credit(client, headers, package_id(client, headers))
    payment_id = checkout.json()["payment_id"]
    stripe.remotes["resource-mismatch"] = ProviderPayment(
        payment_id="provider-mismatch",
        checkout_id="checkout-1",
        status=PaymentStatus.PAID,
        amount=stripe.checkouts[0].amount + (Decimal("1.00") if mismatch == "amount" else Decimal("0")),
        currency="USD" if mismatch == "currency" else stripe.checkouts[0].currency,
        internal_payment_id=payment_id,
    )
    assert webhook(client, "stripe", "evt-mismatch:paid:resource-mismatch").status_code == 409

    async def state() -> tuple[int, PaymentStatus]:
        async with session_factory() as session:
            payment = await session.get(Payment, UUID(payment_id))
            wallet = await session.scalar(select(CreditWallet).where(CreditWallet.user_id == payment.user_id))
            return wallet.available_balance, payment.status

    balance, payment_status = asyncio.run(state())
    assert balance == 100
    assert payment_status == PaymentStatus.FAILED


def test_payment_ownership_history_subscription_and_cancel(
    client: TestClient,
    providers: tuple[FakeProvider, FakeProvider],
    session_factory: async_sessionmaker[AsyncSession],
) -> None:
    stripe = providers[0]
    owner = auth(client, "payment-owner@example.com")
    stranger = auth(client, "payment-stranger@example.com")
    checkout = client.post(
        "/api/v1/payments/subscriptions/checkout",
        headers={**owner, "Idempotency-Key": "subscription-key-1"},
        json={"plan_id": plan_id(client, owner), "provider": "stripe"},
    )
    assert checkout.status_code == 201, checkout.text
    payment_id = checkout.json()["payment_id"]
    assert client.get(f"/api/v1/payments/{payment_id}", headers=stranger).status_code == 404
    assert client.get("/api/v1/payments", headers=stranger).json()["total"] == 0

    async def promote_stranger() -> None:
        async with session_factory() as session:
            admin = await session.scalar(select(User).where(User.email == "payment-stranger@example.com"))
            admin.role = Role.ADMIN
            await session.commit()

    asyncio.run(promote_stranger())
    assert client.get(f"/api/v1/payments/{payment_id}", headers=stranger).status_code == 200
    assert client.get("/api/v1/payments", headers=stranger).json()["total"] == 1
    stripe.remotes["resource-sub"] = ProviderPayment(
        payment_id="invoice-1",
        checkout_id="checkout-1",
        status=PaymentStatus.PAID,
        amount=stripe.checkouts[0].amount,
        currency=stripe.checkouts[0].currency,
        customer_id="customer-1",
        subscription_id="subscription-1",
        period_start=datetime.now(UTC),
        period_end=datetime.now(UTC) + timedelta(days=30),
        internal_payment_id=payment_id,
    )
    assert webhook(client, "stripe", "evt-sub:subscription:resource-sub").status_code == 204
    assert webhook(client, "stripe", "evt-sub:subscription:resource-sub").status_code == 204
    assert client.get(f"/api/v1/payments/{payment_id}", headers=owner).json()["status"] == "paid"
    assert client.post("/api/v1/payments/subscriptions/cancel", headers=owner).status_code == 200
    assert stripe.canceled == ["subscription-1"]

    async def subscription_state() -> tuple[bool, int]:
        async with session_factory() as session:
            user = await session.scalar(select(User).where(User.email == "payment-owner@example.com"))
            subscription = await session.scalar(select(Subscription).where(Subscription.user_id == user.id))
            grants = await session.scalar(
                select(func.count())
                .select_from(CreditTransaction)
                .where(CreditTransaction.idempotency_key.like(f"plan:{subscription.id}:%"))
            )
            return subscription.cancel_at_period_end, grants

    cancel_at_end, grants = asyncio.run(subscription_state())
    assert cancel_at_end is True
    assert grants == 1


def test_declined_out_of_order_and_refund_events_follow_state_machine(
    client: TestClient,
    providers: tuple[FakeProvider, FakeProvider],
    session_factory: async_sessionmaker[AsyncSession],
) -> None:
    stripe = providers[0]
    headers = auth(client, "payment-states@example.com")
    package = package_id(client, headers)

    declined = checkout_credit(client, headers, package, key="declined-checkout")
    declined_id = declined.json()["payment_id"]
    stripe.remotes["resource-declined"] = ProviderPayment(
        payment_id="provider-declined",
        checkout_id="checkout-1",
        status=PaymentStatus.FAILED,
        amount=stripe.checkouts[0].amount,
        currency=stripe.checkouts[0].currency,
        internal_payment_id=declined_id,
    )
    assert webhook(client, "stripe", "evt-declined:failed:resource-declined").status_code == 204

    paid = checkout_credit(client, headers, package, key="paid-state-checkout")
    paid_id = paid.json()["payment_id"]
    stripe.remotes["resource-state"] = ProviderPayment(
        payment_id="provider-state",
        checkout_id="checkout-2",
        status=PaymentStatus.PAID,
        amount=stripe.checkouts[1].amount,
        currency=stripe.checkouts[1].currency,
        internal_payment_id=paid_id,
    )
    assert webhook(client, "stripe", "evt-state-paid:paid:resource-state").status_code == 204
    stripe.remotes["resource-state"] = ProviderPayment(
        payment_id="provider-state",
        checkout_id="checkout-2",
        status=PaymentStatus.FAILED,
        amount=stripe.checkouts[1].amount,
        currency=stripe.checkouts[1].currency,
        internal_payment_id=paid_id,
    )
    assert webhook(client, "stripe", "evt-state-late:failed:resource-state").status_code == 204
    stripe.remotes["resource-state"] = ProviderPayment(
        payment_id="provider-state",
        checkout_id="checkout-2",
        status=PaymentStatus.REFUNDED,
        amount=stripe.checkouts[1].amount,
        currency=stripe.checkouts[1].currency,
        internal_payment_id=paid_id,
    )
    assert webhook(client, "stripe", "evt-state-refund:refund:resource-state").status_code == 204

    async def statuses() -> tuple[PaymentStatus, PaymentStatus]:
        async with session_factory() as session:
            declined_payment = await session.get(Payment, UUID(declined_id))
            paid_payment = await session.get(Payment, UUID(paid_id))
            return declined_payment.status, paid_payment.status

    declined_status, paid_status = asyncio.run(statuses())
    assert declined_status == PaymentStatus.FAILED
    assert paid_status == PaymentStatus.REFUNDED
