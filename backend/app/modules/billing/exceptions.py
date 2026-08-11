from fastapi import status

from app.core.exceptions import DomainError


class EntitlementError(DomainError):
    def __init__(self, detail: str = "AI generation is not available for this account") -> None:
        super().__init__(detail, status.HTTP_403_FORBIDDEN)


class UsageLimitExceeded(DomainError):
    def __init__(self, detail: str = "Monthly usage limit reached") -> None:
        super().__init__(detail, status.HTTP_429_TOO_MANY_REQUESTS)
