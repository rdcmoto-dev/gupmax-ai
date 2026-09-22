from fastapi import status

from app.core.config import get_settings
from app.core.exceptions import DomainError


def require_external_features_enabled() -> None:
    if get_settings().pilot_mode:
        raise DomainError("External paid features are disabled in pilot", status.HTTP_503_SERVICE_UNAVAILABLE)


def require_ai_features_enabled() -> None:
    if get_settings().pilot_mode:
        raise DomainError("External AI features are disabled in pilot", status.HTTP_503_SERVICE_UNAVAILABLE)