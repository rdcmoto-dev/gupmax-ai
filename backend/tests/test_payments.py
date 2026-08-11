import hashlib
import hmac
import json
import time

import pytest

from app.modules.payments.enums import PaymentStatus
from app.modules.payments.exceptions import InvalidWebhook, PaymentConfigurationError
from app.modules.payments.providers.mercado_pago import MercadoPagoProvider
from app.modules.payments.providers.stripe import StripeProvider
from app.modules.payments.service import PaymentStateMachine


def test_payment_state_machine_rejects_regressions() -> None:
    assert PaymentStateMachine.can_transition(PaymentStatus.PENDING, PaymentStatus.PAID)
    assert PaymentStateMachine.can_transition(PaymentStatus.PAID, PaymentStatus.REFUNDED)
    assert not PaymentStateMachine.can_transition(PaymentStatus.PAID, PaymentStatus.FAILED)
    assert not PaymentStateMachine.can_transition(PaymentStatus.REFUNDED, PaymentStatus.PAID)


def test_stripe_requires_environment_matching_key() -> None:
    with pytest.raises(PaymentConfigurationError):
        StripeProvider("sk_live_placeholder", "whsec_test", production=False, timeout=5)
    with pytest.raises(PaymentConfigurationError):
        StripeProvider("sk_test_placeholder", "whsec_test", production=True, timeout=5)


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
    manifest = "id:123;request-id:req-1;ts:123456;"
    signature = hmac.new(b"mp_secret", manifest.encode(), hashlib.sha256).hexdigest()
    notification = provider.verify_webhook(
        payload,
        {"x-signature": f"ts=123456,v1={signature}", "x-request-id": "req-1"},
        {},
    )
    assert notification.resource_id == "123"
    with pytest.raises(InvalidWebhook):
        provider.verify_webhook(
            payload,
            {"x-signature": "ts=123456,v1=forged", "x-request-id": "req-1"},
            {},
        )
