import asyncio
import hashlib
import hmac
import json
import time
from decimal import Decimal
from urllib.parse import parse_qs

import httpx
import pytest

from app.modules.payments.contracts import CheckoutInput
from app.modules.payments.enums import PaymentStatus
from app.modules.payments.exceptions import InvalidWebhook, PaymentConfigurationError
from app.modules.payments.providers.mercado_pago import MercadoPagoProvider
from app.modules.payments.providers.stripe import StripeProvider
from app.modules.payments.service import PaymentStateMachine, frontend_route_url


def test_payment_state_machine_rejects_regressions() -> None:
    assert PaymentStateMachine.can_transition(PaymentStatus.PENDING, PaymentStatus.PAID)
    assert PaymentStateMachine.can_transition(PaymentStatus.PAID, PaymentStatus.REFUNDED)
    assert not PaymentStateMachine.can_transition(PaymentStatus.PAID, PaymentStatus.FAILED)
    assert not PaymentStateMachine.can_transition(PaymentStatus.REFUNDED, PaymentStatus.PAID)


def test_frontend_return_url_uses_flutter_hash_routing_and_configured_base() -> None:
    assert (
        frontend_route_url("http://localhost:61895/", "/payments/success")
        == "http://localhost:61895/#/payments/success"
    )
    assert (
        frontend_route_url("https://app.example.com", "payments/cancel")
        == "https://app.example.com/#/payments/cancel"
    )


def test_stripe_requires_environment_matching_key() -> None:
    with pytest.raises(PaymentConfigurationError):
        StripeProvider("sk_live_placeholder", "whsec_test", production=False, timeout=5)
    with pytest.raises(PaymentConfigurationError):
        StripeProvider("sk_test_placeholder", "whsec_test", production=True, timeout=5)


def test_mercado_pago_accepts_opaque_test_credentials_and_rejects_detectable_test_token_in_production() -> None:
    provider = MercadoPagoProvider("opaque-test-credential", "mp_secret", production=False, timeout=5)
    assert provider.access_token == "opaque-test-credential"
    with pytest.raises(PaymentConfigurationError):
        MercadoPagoProvider("TEST-placeholder", "mp_secret", production=True, timeout=5)


def test_mercado_pago_checkout_sends_numeric_unit_price_and_valid_preference_payload(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            201,
            json={
                "id": "pref-test-1",
                "sandbox_init_point": "https://sandbox.mercadopago.test/checkout/pref-test-1",
            },
        )

    transport = httpx.MockTransport(handler)
    async_client = httpx.AsyncClient

    class MockAsyncClient(async_client):
        def __init__(self, *args: object, **kwargs: object) -> None:
            super().__init__(*args, transport=transport, **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", MockAsyncClient)
    provider = MercadoPagoProvider("opaque-test-credential", "mp_secret", production=False, timeout=5)
    checkout = asyncio.run(
        provider.create_checkout(
            CheckoutInput(
                internal_payment_id="10000000-0000-0000-0000-000000000001",
                idempotency_key="checkout-test-001",
                title="500 créditos",
                amount=Decimal("19.90"),
                currency="BRL",
                customer_email="mercado-pago-test@example.com",
                success_url="https://example.test/payments/success",
                cancel_url="https://example.test/payments/cancel",
                webhook_url="https://api.example.test/api/v1/payments/webhooks/mercado-pago",
            )
        )
    )

    assert checkout.checkout_id == "pref-test-1"
    assert len(requests) == 1
    request = requests[0]
    assert request.method == "POST"
    assert request.url == "https://api.mercadopago.com/checkout/preferences"
    assert request.headers["x-idempotency-key"] == "checkout-test-001"
    payload = json.loads(request.content)
    assert payload == {
        "external_reference": "10000000-0000-0000-0000-000000000001",
        "items": [
            {
                "title": "500 créditos",
                "quantity": 1,
                "unit_price": 19.9,
                "currency_id": "BRL",
            }
        ],
        "back_urls": {
            "success": "https://example.test/payments/success",
            "failure": "https://example.test/payments/cancel",
            "pending": "https://example.test/payments/success",
        },
        "notification_url": "https://api.example.test/api/v1/payments/webhooks/mercado-pago",
    }


def test_mercado_pago_reconciliation_search_is_read_only_and_requires_exact_reference(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    requests: list[httpx.Request] = []
    external_reference = "10000000-0000-0000-0000-000000000001"

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json={
                "results": [
                    {
                        "id": 123,
                        "status": "approved",
                        "transaction_amount": 19.9,
                        "currency_id": "BRL",
                        "external_reference": external_reference,
                    },
                    {
                        "id": 999,
                        "status": "approved",
                        "transaction_amount": 999,
                        "currency_id": "BRL",
                        "external_reference": "different-payment",
                    },
                ]
            },
        )

    transport = httpx.MockTransport(handler)
    async_client = httpx.AsyncClient

    class MockAsyncClient(async_client):
        def __init__(self, *args: object, **kwargs: object) -> None:
            super().__init__(*args, transport=transport, **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", MockAsyncClient)
    provider = MercadoPagoProvider("opaque-test-credential", "mp_secret", production=False, timeout=5)
    remote = asyncio.run(provider.find_payment_by_external_reference(external_reference))

    assert remote is not None
    assert remote.payment_id == "123"
    assert remote.internal_payment_id == external_reference
    assert remote.status == PaymentStatus.PAID
    assert len(requests) == 1
    assert requests[0].method == "GET"
    assert requests[0].url.params["external_reference"] == external_reference


def test_stripe_checkout_uses_async_form_request_and_idempotency_header(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    requests: list[httpx.Request] = []
    frontend_url = "https://app.example.test"
    success_url = f"{frontend_url}/#/payments/success"
    cancel_url = f"{frontend_url}/#/payments/cancel"

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json={"id": "cs_test_1", "url": "https://checkout.stripe.test/c/pay/cs_test_1"},
        )

    transport = httpx.MockTransport(handler)
    async_client = httpx.AsyncClient

    class MockAsyncClient(async_client):
        def __init__(self, *args: object, **kwargs: object) -> None:
            super().__init__(*args, transport=transport, **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", MockAsyncClient)
    provider = StripeProvider("sk_test_placeholder", "whsec_test", production=False, timeout=5)
    checkout = asyncio.run(
        provider.create_checkout(
            CheckoutInput(
                internal_payment_id="10000000-0000-0000-0000-000000000001",
                idempotency_key="checkout-test-001",
                title="500 créditos",
                amount=Decimal("19.90"),
                currency="BRL",
                customer_email="stripe-test@example.com",
                success_url=success_url,
                cancel_url=cancel_url,
                webhook_url="http://localhost:8000/api/v1/payments/webhooks/stripe",
            )
        )
    )

    assert checkout.checkout_id == "cs_test_1"
    assert len(requests) == 1
    request = requests[0]
    assert request.method == "POST"
    assert request.url == "https://api.stripe.com/v1/checkout/sessions"
    assert request.headers["idempotency-key"] == "checkout-test-001"
    assert request.headers["content-type"].startswith("application/x-www-form-urlencoded")
    form = parse_qs(request.content.decode())
    assert form["mode"] == ["payment"]
    assert form["success_url"] == [success_url]
    assert form["cancel_url"] == [cancel_url]
    assert form["line_items[0][price_data][unit_amount]"] == ["1990"]
    assert form["line_items[0][price_data][currency]"] == ["brl"]


def test_stripe_webhook_uses_raw_payload_hmac_and_timestamp() -> None:
    provider = StripeProvider("sk_test_placeholder", "whsec_test", production=False, timeout=5)
    payload = json.dumps(
        {"id": "evt_1", "type": "checkout.session.completed", "data": {"object": {"id": "cs_1"}}},
        separators=(",", ":"),
    ).encode()
    timestamp = int(time.time())
    signature = hmac.new(b"whsec_test", f"{timestamp}.".encode() + payload, hashlib.sha256).hexdigest()
    notification = provider.verify_webhook(payload, {"stripe-signature": f"t={timestamp},v1={signature}"}, {})
    assert notification.event_id == "evt_1"
    with pytest.raises(InvalidWebhook):
        provider.verify_webhook(payload, {"stripe-signature": f"t={timestamp},v1=forged"}, {})


def test_mercado_pago_webhook_uses_official_manifest_fields() -> None:
    provider = MercadoPagoProvider("TEST-placeholder", "mp_secret", production=False, timeout=5)
    payload = b'{"id":"notification-1","type":"payment","data":{"id":"123"}}'
    timestamp = str(int(time.time()))
    manifest = f"id:123;request-id:req-1;ts:{timestamp};"
    signature = hmac.new(b"mp_secret", manifest.encode(), hashlib.sha256).hexdigest()
    notification = provider.verify_webhook(
        payload,
        {"x-signature": f"ts={timestamp},v1={signature}", "x-request-id": "req-1"},
        {},
    )
    assert notification.resource_id == "123"
    assert notification.relevant is True
    with pytest.raises(InvalidWebhook):
        provider.verify_webhook(
            payload,
            {"x-signature": f"ts={timestamp},v1=forged", "x-request-id": "req-1"},
            {},
        )
    with pytest.raises(InvalidWebhook):
        old_timestamp = str(int(time.time()) - 301)
        old_manifest = f"id:123;request-id:req-1;ts:{old_timestamp};"
        old_signature = hmac.new(b"mp_secret", old_manifest.encode(), hashlib.sha256).hexdigest()
        provider.verify_webhook(
            payload,
            {"x-signature": f"ts={old_timestamp},v1={old_signature}", "x-request-id": "req-1"},
            {},
        )


def test_mercado_pago_valid_irrelevant_webhook_is_classified_for_safe_ignore() -> None:
    provider = MercadoPagoProvider("opaque-test-credential", "mp_secret", production=False, timeout=5)
    payload = b'{"id":"notification-2","type":"merchant_order","data":{"id":"456"}}'
    timestamp = str(int(time.time()))
    manifest = f"id:456;request-id:req-2;ts:{timestamp};"
    signature = hmac.new(b"mp_secret", manifest.encode(), hashlib.sha256).hexdigest()

    notification = provider.verify_webhook(
        payload,
        {"x-signature": f"ts={timestamp},v1={signature}", "x-request-id": "req-2"},
        {},
    )

    assert notification.event_type == "merchant_order"
    assert notification.relevant is False


def test_mercado_pago_official_payment_simulation_is_classified_for_safe_ignore() -> None:
    provider = MercadoPagoProvider("opaque-test-credential", "mp_secret", production=False, timeout=5)
    payload = json.dumps(
        {
            "action": "payment.updated",
            "api_version": "v1",
            "data": {"id": "123456"},
            "date_created": "2021-11-01T02:02:02Z",
            "id": 123456,
            "live_mode": False,
            "type": "payment",
            "user_id": 123456,
        },
        separators=(",", ":"),
    ).encode()
    timestamp = str(int(time.time()))
    manifest = f"id:123456;request-id:req-simulation;ts:{timestamp};"
    signature = hmac.new(b"mp_secret", manifest.encode(), hashlib.sha256).hexdigest()

    notification = provider.verify_webhook(
        payload,
        {"x-signature": f"ts={timestamp},v1={signature}", "x-request-id": "req-simulation"},
        {"data.id": "123456", "type": "payment"},
    )

    assert notification.event_id == "123456"
    assert notification.event_type == "payment.updated"
    assert notification.resource_id == "123456"
    assert notification.relevant is False
