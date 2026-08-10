from fastapi import status

from app.core.exceptions import DomainError


class AIGatewayError(DomainError):
    """Base error exposed by AI providers without provider internals."""


class AIConfigurationError(AIGatewayError):
    def __init__(self) -> None:
        super().__init__("AI provider is unavailable", status.HTTP_503_SERVICE_UNAVAILABLE)


class AIRequestError(AIGatewayError):
    def __init__(self) -> None:
        super().__init__("AI request could not be processed", status.HTTP_400_BAD_REQUEST)


class AIUnavailableError(AIGatewayError):
    def __init__(self) -> None:
        super().__init__("AI generation is temporarily unavailable", status.HTTP_503_SERVICE_UNAVAILABLE)
