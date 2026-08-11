"""Perform one read-only Stripe test authentication request."""

from __future__ import annotations

import sys

import httpx

from app.core.config import get_settings


def report(environment: str, authentication: str, context: str, status_http: str) -> None:
    print(f"ambiente: {environment}")
    print(f"autenticação: {authentication}")
    print(f"account/test context: {context}")
    print(f"status HTTP: {status_http}")


def main() -> int:
    settings = get_settings()
    environment = settings.payments_environment.lower()
    if environment not in {"test", "sandbox"}:
        report(environment, "FAIL", "bloqueado: ambiente não sandbox", "N/A")
        return 1

    secret = settings.stripe_secret_key.get_secret_value() if settings.stripe_secret_key else ""
    if not secret.startswith("sk_test_"):
        report(environment, "FAIL", "bloqueado: chave não é sk_test_", "N/A")
        return 1

    try:
        response = httpx.get(
            "https://api.stripe.com/v1/account",
            headers={"Authorization": f"Bearer {secret}"},
            timeout=settings.payments_timeout_seconds,
        )
    except httpx.HTTPError:
        report(environment, "FAIL", "test; conta indisponível", "N/A")
        return 1

    if response.status_code != 200:
        report(environment, "FAIL", "test; autenticação rejeitada", str(response.status_code))
        return 1

    try:
        account_id = str(response.json()["id"])
    except (KeyError, TypeError, ValueError):
        report(environment, "FAIL", "test; resposta inválida", str(response.status_code))
        return 1
    masked_account = f"{account_id[:5]}…{account_id[-4:]}" if len(account_id) > 9 else "conta test confirmada"
    report(environment, "OK", f"test; {masked_account}", str(response.status_code))
    return 0


if __name__ == "__main__":
    sys.exit(main())
