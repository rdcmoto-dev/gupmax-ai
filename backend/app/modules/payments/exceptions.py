from fastapi import status

from app.core.exceptions import DomainError


class PaymentConfigurationError(DomainError):
    def __init__(self) -> None:
        super().__init__("Payment provider is not configured", status.HTTP_503_SERVICE_UNAVAILABLE)


class PaymentProviderError(DomainError):
    def __init__(self, detail: str = "Payment provider is unavailable") -> None:
        super().__init__(detail, status.HTTP_502_BAD_GATEWAY)


class InvalidWebhook(DomainError):
    def __init__(self) -> None:
        super().__init__("Invalid webhook signature", status.HTTP_400_BAD_REQUEST)
