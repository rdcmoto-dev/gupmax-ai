import hashlib
import hmac
import json
import time
from datetime import UTC, datetime
from decimal import Decimal

import httpx

from app.modules.payments.contracts import (
    CheckoutInput,
    CheckoutOutput,
    ProviderPayment,
    WebhookNotification,
)
from app.modules.payments.enums import PaymentProviderName, PaymentStatus
from app.modules.payments.exceptions import InvalidWebhook, PaymentConfigurationError, PaymentProviderError


class StripeProvider:
    name = PaymentProviderName.STRIPE
    api_base = "https://api.stripe.com/v1"

    def __init__(
        self,
        secret_key: str | None,
        webhook_secret: str | None,
        *,
        production: bool,
        timeout: float,
    ) -> None:
        if not secret_key or not webhook_secret:
            raise PaymentConfigurationError()
        if production != secret_key.startswith("sk_live_"):
            raise PaymentConfigurationError()
        self.secret_key = secret_key
        self.webhook_secret = webhook_secret
        self.timeout = timeout

    async def _request(self, method: str, path: str, **kwargs: object) -> dict[str, object]:
        headers = {"Authorization": f"Bearer {self.secret_key}"}
        headers.update(kwargs.pop("headers", {}))
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.request(method, f"{self.api_base}{path}", headers=headers, **kwargs)
                response.raise_for_status()
                return response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise PaymentProviderError() from exc

    async def create_checkout(self, data: CheckoutInput) -> CheckoutOutput:
        form: list[tuple[str, str]] = [
            ("mode", "subscription" if data.recurring else "payment"),
            ("success_url", data.success_url),
            ("cancel_url", data.cancel_url),
            ("customer_email", data.customer_email),
            ("client_reference_id", data.internal_payment_id),
            ("metadata[internal_payment_id]", data.internal_payment_id),
            ("line_items[0][quantity]", "1"),
            ("line_items[0][price_data][currency]", data.currency.lower()),
            ("line_items[0][price_data][unit_amount]", str(int(data.amount * 100))),
            ("line_items[0][price_data][product_data][name]", data.title),
        ]
        if data.recurring:
            form.append(("line_items[0][price_data][recurring][interval]", data.interval or "month"))
            form.append(("subscription_data[metadata][internal_payment_id]", data.internal_payment_id))
        headers = {"Idempotency-Key": data.idempotency_key}
        result = await self._request("POST", "/checkout/sessions", data=form, headers=headers)
        return CheckoutOutput(checkout_id=str(result["id"]), checkout_url=str(result["url"]))

    def verify_webhook(self, payload: bytes, headers: dict[str, str], query: dict[str, str]) -> WebhookNotification:
        del query
        signature = headers.get("stripe-signature", "")
        parts = dict(item.split("=", 1) for item in signature.split(",") if "=" in item)
        try:
            timestamp = int(parts["t"])
            supplied = parts["v1"]
        except (KeyError, ValueError) as exc:
            raise InvalidWebhook() from exc
        if abs(time.time() - timestamp) > 300:
            raise InvalidWebhook()
        signed = f"{timestamp}.".encode() + payload
        expected = hmac.new(self.webhook_secret.encode(), signed, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, supplied):
            raise InvalidWebhook()
        try:
            event = json.loads(payload)
            resource = event["data"]["object"]
            return WebhookNotification(str(event["id"]), str(event["type"]), str(resource["id"]))
        except (KeyError, TypeError, ValueError) as exc:
            raise InvalidWebhook() from exc

    async def get_payment(self, resource_id: str) -> ProviderPayment:
        if resource_id.startswith("sub_"):
            subscription = await self._request("GET", f"/subscriptions/{resource_id}")
            status = (
                PaymentStatus.PAID if subscription.get("status") in {"active", "trialing"} else PaymentStatus.FAILED
            )
            return ProviderPayment(
                payment_id=resource_id,
                checkout_id=None,
                status=status,
                amount=Decimal("0"),
                currency=str(subscription.get("currency", "")).upper(),
                customer_id=str(subscription.get("customer")) if subscription.get("customer") else None,
                subscription_id=resource_id,
                period_start=datetime.fromtimestamp(int(subscription["current_period_start"]), UTC),
                period_end=datetime.fromtimestamp(int(subscription["current_period_end"]), UTC),
                internal_payment_id=(subscription.get("metadata") or {}).get("internal_payment_id"),
            )
        session = await self._request("GET", f"/checkout/sessions/{resource_id}")
        status = PaymentStatus.PAID if session.get("payment_status") == "paid" else PaymentStatus.PROCESSING
        return ProviderPayment(
            payment_id=str(session.get("payment_intent") or session.get("subscription") or resource_id),
            checkout_id=str(session["id"]),
            status=status,
            amount=Decimal(str(session.get("amount_total", 0))) / 100,
            currency=str(session.get("currency", "")).upper(),
            customer_id=str(session.get("customer")) if session.get("customer") else None,
            subscription_id=str(session.get("subscription")) if session.get("subscription") else None,
            internal_payment_id=str(session.get("client_reference_id") or "") or None,
        )

    async def cancel_subscription(self, subscription_id: str) -> None:
        await self._request("POST", f"/subscriptions/{subscription_id}", data={"cancel_at_period_end": "true"})
