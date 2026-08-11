from fastapi import status

from app.core.exceptions import DomainError


class InsufficientCredits(DomainError):
    def __init__(self) -> None:
        super().__init__("Insufficient credits", status.HTTP_402_PAYMENT_REQUIRED)


class CreditCostRuleNotFound(DomainError):
    def __init__(self) -> None:
        super().__init__("Credit cost is not configured for this operation", status.HTTP_503_SERVICE_UNAVAILABLE)
