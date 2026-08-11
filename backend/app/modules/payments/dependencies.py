from typing import Annotated

from fastapi import Depends

from app.core.config import get_settings
from app.modules.payments.contracts import PaymentProvider
from app.modules.payments.enums import PaymentProviderName, PaymentsEnvironment
from app.modules.payments.exceptions import PaymentConfigurationError
from app.modules.payments.providers.mercado_pago import MercadoPagoProvider
from app.modules.payments.providers.stripe import StripeProvider


class PaymentProviderRegistry:
    def __init__(self, providers: dict[PaymentProviderName, PaymentProvider]) -> None:
        self.providers = providers

    def get(self, name: PaymentProviderName) -> PaymentProvider:
        provider = self.providers.get(name)
        if provider is None:
            raise PaymentConfigurationError()
        return provider


def get_payment_provider_registry() -> PaymentProviderRegistry:
    settings = get_settings()
    try:
        environment = PaymentsEnvironment(settings.payments_environment)
    except ValueError as exc:
        raise PaymentConfigurationError() from exc
    production = environment == PaymentsEnvironment.PRODUCTION
    providers: dict[PaymentProviderName, PaymentProvider] = {}
    stripe_key = settings.stripe_secret_key.get_secret_value() if settings.stripe_secret_key else None
    stripe_webhook = settings.stripe_webhook_secret.get_secret_value() if settings.stripe_webhook_secret else None
    if stripe_key or stripe_webhook:
        providers[PaymentProviderName.STRIPE] = StripeProvider(
            stripe_key,
            stripe_webhook,
            production=production,
            timeout=settings.payments_timeout_seconds,
        )
    mp_token = settings.mercado_pago_access_token.get_secret_value() if settings.mercado_pago_access_token else None
    mp_webhook = (
        settings.mercado_pago_webhook_secret.get_secret_value() if settings.mercado_pago_webhook_secret else None
    )
    if mp_token or mp_webhook:
        providers[PaymentProviderName.MERCADO_PAGO] = MercadoPagoProvider(
            mp_token,
            mp_webhook,
            production=production,
            timeout=settings.payments_timeout_seconds,
        )
    return PaymentProviderRegistry(providers)


ProviderRegistry = Annotated[PaymentProviderRegistry, Depends(get_payment_provider_registry)]
