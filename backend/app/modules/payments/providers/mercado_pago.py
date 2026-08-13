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


class MercadoPagoProvider:
    name = PaymentProviderName.MERCADO_PAGO
    api_base = "https://api.mercadopago.com"

    def __init__(
        self, access_token: str | None, webhook_secret: str | None, *, production: bool, timeout: float
    ) -> None:
        if not access_token or not webhook_secret:
            raise PaymentConfigurationError()
        if production and access_token.startswith("TEST-"):
            raise PaymentConfigurationError()
        self.access_token = access_token
        self.webhook_secret = webhook_secret
        self.timeout = timeout

    async def _request(self, method: str, path: str, **kwargs: object) -> dict[str, object]:
        headers = {"Authorization": f"Bearer {self.access_token}"}
        headers.update(kwargs.pop("headers", {}))
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.request(method, f"{self.api_base}{path}", headers=headers, **kwargs)
                response.raise_for_status()
                return response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise PaymentProviderError() from exc

    async def create_checkout(self, data: CheckoutInput) -> CheckoutOutput:
        if data.recurring:
            payload = {
                "reason": data.title,
                "external_reference": data.internal_payment_id,
                "payer_email": data.customer_email,
                "back_url": data.success_url,
                "auto_recurring": {
                    "frequency": 1,
                    "frequency_type": "months",
                    "transaction_amount": str(data.amount),
                    "currency_id": data.currency,
                },
            }
            result = await self._request("POST", "/preapproval", json=payload)
        else:
            payload = {
                "external_reference": data.internal_payment_id,
                "items": [
                    {
                        "title": data.title,
                        "quantity": 1,
                        "unit_price": float(data.amount),
                        "currency_id": data.currency,
                    }
                ],
                "back_urls": {"success": data.success_url, "failure": data.cancel_url, "pending": data.success_url},
                "notification_url": data.webhook_url,
            }
            result = await self._request(
                "POST", "/checkout/preferences", json=payload, headers={"X-Idempotency-Key": data.idempotency_key}
            )
        checkout_url = result.get("sandbox_init_point") or result.get("init_point")
        return CheckoutOutput(checkout_id=str(result["id"]), checkout_url=str(checkout_url))

    def verify_webhook(self, payload: bytes, headers: dict[str, str], query: dict[str, str]) -> WebhookNotification:
        signature = headers.get("x-signature", "")
        request_id = headers.get("x-request-id", "")
        parts = dict(item.strip().split("=", 1) for item in signature.split(",") if "=" in item)
        data_id = query.get("data.id") or query.get("id")
        try:
            timestamp, supplied = parts["ts"], parts["v1"]
            timestamp_seconds = int(timestamp)
            body = json.loads(payload or b"{}")
            data_id = data_id or str(body.get("data", {}).get("id") or body.get("id"))
            event_id = str(body.get("id") or f"{body.get('type')}:{data_id}:{timestamp}")
            event_type = str(body.get("action") or body.get("type"))
        except (KeyError, TypeError, ValueError) as exc:
            raise InvalidWebhook() from exc
        if abs(time.time() - timestamp_seconds) > 300:
            raise InvalidWebhook()
        manifest = f"id:{data_id};request-id:{request_id};ts:{timestamp};"
        expected = hmac.new(self.webhook_secret.encode(), manifest.encode(), hashlib.sha256).hexdigest()
        if not data_id or not request_id or not hmac.compare_digest(expected, supplied):
            raise InvalidWebhook()
        is_official_simulation = (
            body.get("live_mode") is False
            and str(body.get("id")) == "123456"
            and data_id == "123456"
            and body.get("type") == "payment"
        )
        return WebhookNotification(
            event_id,
            event_type,
            data_id,
            relevant=not is_official_simulation
            and (event_type == "payment" or event_type.startswith("payment.")),
        )

    async def get_payment(self, resource_id: str) -> ProviderPayment:
        result = await self._request("GET", f"/v1/payments/{resource_id}")
        return self._payment_from_result(result, include_order_checkout=True)

    async def find_payment_by_external_reference(self, external_reference: str) -> ProviderPayment | None:
        result = await self._request(
            "GET",
            "/v1/payments/search",
            params={"external_reference": external_reference, "sort": "date_created", "criteria": "desc"},
        )
        matches = [
            item
            for item in result.get("results", [])
            if isinstance(item, dict) and str(item.get("external_reference") or "") == external_reference
        ]
        if not matches:
            return None
        approved = next((item for item in matches if item.get("status") == "approved"), None)
        return self._payment_from_result(approved or matches[0], include_order_checkout=False)

    @staticmethod
    def _payment_from_result(result: dict[str, object], *, include_order_checkout: bool) -> ProviderPayment:
        statuses = {
            "approved": PaymentStatus.PAID,
            "in_process": PaymentStatus.PROCESSING,
            "pending": PaymentStatus.PENDING,
            "cancelled": PaymentStatus.CANCELED,
            "rejected": PaymentStatus.FAILED,
            "refunded": PaymentStatus.REFUNDED,
        }
        return ProviderPayment(
            payment_id=str(result["id"]),
            checkout_id=(
                str(result.get("order", {}).get("id")) if include_order_checkout and result.get("order") else None
            ),
            status=statuses.get(str(result.get("status")), PaymentStatus.PROCESSING),
            amount=Decimal(str(result.get("transaction_amount", 0))),
            currency=str(result.get("currency_id", "")),
            customer_id=str(result.get("payer", {}).get("id")) if result.get("payer") else None,
            subscription_id=str(result.get("preapproval_id")) if result.get("preapproval_id") else None,
            period_start=datetime.now(UTC),
            internal_payment_id=str(result.get("external_reference") or "") or None,
        )

    async def cancel_subscription(self, subscription_id: str) -> None:
        await self._request("PUT", f"/preapproval/{subscription_id}", json={"status": "cancelled"})
