import asyncio
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from typing import Any
from uuid import uuid4

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.main import app
from app.modules.ai_gateway.dependencies import get_ai_gateway_service
from app.modules.ai_gateway.schemas import GenerateTextResponse, TokenUsageResponse
from app.modules.credits.enums import CreditOperationType, CreditSource, CreditTransactionType, ReservationStatus
from app.modules.credits.model import CreditLot, CreditReservation, CreditTransaction, CreditWallet
from app.modules.credits.service import CreditService
from app.modules.users.model import User
from app.modules.users.roles import Role


class FakeGateway:
    calls = 0

    async def generate(self, data: Any) -> GenerateTextResponse:
        self.calls += 1
        return GenerateTextResponse(
            provider="fake",
            model="fake-model",
            text=data.user_prompt,
            latency_ms=1,
            usage=TokenUsageResponse(input_tokens=12, output_tokens=5, total_tokens=17),
        )


class FailingGateway:
    async def generate(self, _data: object) -> GenerateTextResponse:
        raise RuntimeError("provider timeout")


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Credit User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def prompt(client: TestClient, headers: dict[str, str], optimize: bool):
    return client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={"input": "Crie uma campanha de lançamento", "optimize_with_ai": optimize},
    )


def test_credit_endpoints_require_authentication(client: TestClient) -> None:
    for path in ("wallet", "transactions", "packages", "costs"):
        assert client.get(f"/api/v1/credits/{path}").status_code == 401
    assert client.post("/api/v1/credits/estimate", json={"operation_type": "prompt_optimization"}).status_code == 401


def test_trial_wallet_packages_costs_and_estimate(client: TestClient) -> None:
    headers = auth(client, "credits@example.com")
    wallet = client.get("/api/v1/credits/wallet", headers=headers)
    assert wallet.status_code == 200
    assert wallet.json()["available_balance"] == 100
    assert wallet.json()["reserved_balance"] == 0
    transactions = client.get("/api/v1/credits/transactions", headers=headers).json()
    assert transactions["total"] == 1
    assert transactions["items"][0]["type"] == "trial_grant"
    assert len(client.get("/api/v1/credits/packages", headers=headers).json()) == 4
    assert len(client.get("/api/v1/credits/costs", headers=headers).json()) >= 2
    estimate = client.post(
        "/api/v1/credits/estimate",
        headers=headers,
        json={"operation_type": "prompt_optimization", "estimated_input_tokens": 100, "max_output_tokens": 100},
    )
    assert estimate.status_code == 200
    assert estimate.json()["can_execute"] is True
    assert estimate.json()["estimated_credits"] > 0


def test_deterministic_is_free_and_ai_settles_ledger(client: TestClient) -> None:
    headers = auth(client, "credit-ai@example.com")
    before = client.get("/api/v1/credits/wallet", headers=headers).json()
    assert prompt(client, headers, False).status_code == 201
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == before

    app.dependency_overrides[get_ai_gateway_service] = lambda: FakeGateway()
    try:
        response = prompt(client, headers, True)
    finally:
        app.dependency_overrides.pop(get_ai_gateway_service, None)
    assert response.status_code == 201, response.text
    wallet = client.get("/api/v1/credits/wallet", headers=headers).json()
    assert wallet["available_balance"] < 100
    assert wallet["reserved_balance"] == 0
    ledger = client.get("/api/v1/credits/transactions", headers=headers).json()["items"]
    assert any(item["type"] == "reservation" for item in ledger)
    assert any(item["type"] == "ai_usage" and item["amount"] < 0 for item in ledger)


def test_ai_prompt_generation_is_idempotent_end_to_end(client: TestClient) -> None:
    headers = auth(client, "credit-ai-idempotent@example.com")
    headers["Idempotency-Key"] = "prompt-generation-001"
    gateway = FakeGateway()
    app.dependency_overrides[get_ai_gateway_service] = lambda: gateway
    try:
        first = prompt(client, headers, True)
        balance_after_first = client.get("/api/v1/credits/wallet", headers=headers).json()
        second = prompt(client, headers, True)
    finally:
        app.dependency_overrides.pop(get_ai_gateway_service, None)

    assert first.status_code == second.status_code == 201
    assert first.json()["id"] == second.json()["id"]
    assert gateway.calls == 1
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == balance_after_first
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == 1
    ledger = client.get("/api/v1/credits/transactions", headers=headers).json()["items"]
    assert len([item for item in ledger if item["type"] == "ai_usage"]) == 1

    conflict = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={"input": "Outra solicitação", "optimize_with_ai": True},
    )
    assert conflict.status_code == 409


def test_provider_failure_releases_reservation(
    client: TestClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    headers = auth(client, "credit-failure@example.com")
    app.dependency_overrides[get_ai_gateway_service] = lambda: FailingGateway()
    try:
        try:
            prompt(client, headers, True)
        except RuntimeError:
            pass
    finally:
        app.dependency_overrides.pop(get_ai_gateway_service, None)
    wallet = client.get("/api/v1/credits/wallet", headers=headers).json()
    assert wallet["available_balance"] == 100
    assert wallet["reserved_balance"] == 0
    fallback = client.get("/api/v1/prompts", headers=headers).json()
    assert fallback["total"] == 1
    assert fallback["items"][0]["status"] == "generated"
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == 0

    async def status_value() -> ReservationStatus:
        async with session_factory() as session:
            reservation = await session.scalar(select(CreditReservation))
            assert reservation is not None
            return reservation.status

    assert asyncio.run(status_value()) == ReservationStatus.RELEASED


def test_insufficient_balance_blocks_before_provider(
    client: TestClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    headers = auth(client, "credit-empty@example.com")

    async def empty() -> None:
        async with session_factory() as session:
            user = await session.scalar(select(User).where(User.email == "credit-empty@example.com"))
            wallet = await session.scalar(select(CreditWallet).where(CreditWallet.user_id == user.id))
            wallet.available_balance = 0
            for lot in (await session.scalars(select(CreditLot))).all():
                lot.available_amount = 0
            await session.commit()

    asyncio.run(empty())
    app.dependency_overrides[get_ai_gateway_service] = lambda: FakeGateway()
    try:
        response = prompt(client, headers, True)
    finally:
        app.dependency_overrides.pop(get_ai_gateway_service, None)
    assert response.status_code == 402


def test_idempotent_grant_refund_and_fefo_lot_consumption(
    client: TestClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    auth(client, "credit-ledger@example.com")

    async def exercise() -> tuple[bool, bool, CreditSource]:
        async with session_factory() as session:
            user = await session.scalar(select(User).where(User.email == "credit-ledger@example.com"))
            service = CreditService(session)
            first = await service.grant(
                user.id,
                10,
                source=CreditSource.PROMOTIONAL,
                transaction_type=CreditTransactionType.PROMOTION,
                reference_type="campaign",
                reference_id="campaign-1",
                idempotency_key="promotion:campaign-1:user",
                description="Promotion",
                expires_at=datetime.now(UTC) + timedelta(hours=1),
            )
            duplicate = await service.grant(
                user.id,
                10,
                source=CreditSource.PROMOTIONAL,
                transaction_type=CreditTransactionType.PROMOTION,
                reference_type="campaign",
                reference_id="campaign-1",
                idempotency_key="promotion:campaign-1:user",
                description="Promotion",
            )
            reservation = await service.reserve(
                user.id, CreditOperationType.PROMPT_OPTIMIZATION, "openai", None, 0, 0, "fefo-reservation"
            )
            refund = await service.refund(user.id, 2, reservation.id, "refund-1")
            duplicate_refund = await service.refund(user.id, 2, reservation.id, "refund-1")
            return first.id == duplicate.id, refund.id == duplicate_refund.id, reservation.allocations[0].lot.source

    grant_same, refund_same, source = asyncio.run(exercise())
    assert grant_same and refund_same
    assert source == CreditSource.PROMOTIONAL


def test_admin_adjustment_is_audited_and_user_is_forbidden(
    client: TestClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    user_headers = auth(client, "adjusted@example.com")
    assert (
        client.post(
            "/api/v1/credits/adjustments",
            headers=user_headers,
            json={
                "user_id": "10000000-0000-0000-0000-000000000001",
                "amount": 10,
                "reason": "Manual correction",
                "idempotency_key": "adjust-001",
            },
        ).status_code
        == 403
    )
    admin_headers = auth(client, "credit-admin@example.com")

    async def promote_and_target() -> str:
        async with session_factory() as session:
            admin = await session.scalar(select(User).where(User.email == "credit-admin@example.com"))
            target = await session.scalar(select(User).where(User.email == "adjusted@example.com"))
            admin.role = Role.ADMIN
            await session.commit()
            return str(target.id)

    target_id = asyncio.run(promote_and_target())
    response = client.post(
        "/api/v1/credits/adjustments",
        headers=admin_headers,
        json={"user_id": target_id, "amount": 25, "reason": "Support correction", "idempotency_key": "adjust-002"},
    )
    assert response.status_code == 201, response.text
    assert response.json()["type"] == "adjustment"
    assert response.json()["amount"] == 25


def test_expiration_and_plan_grant_are_idempotent(
    client: TestClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    auth(client, "credit-expiration@example.com")

    async def exercise() -> tuple[int, bool, int]:
        async with session_factory() as session:
            user = await session.scalar(select(User).where(User.email == "credit-expiration@example.com"))
            service = CreditService(session)
            await service.grant(
                user.id,
                7,
                source=CreditSource.PROMOTIONAL,
                transaction_type=CreditTransactionType.PROMOTION,
                reference_type="expired_campaign",
                reference_id="expired-1",
                idempotency_key="expired-promotion-1",
                description="Expired promotion",
                expires_at=datetime.now(UTC) - timedelta(seconds=1),
            )
            wallet_after_expiry = await service.wallet(user.id)
            balance_after_expiry = wallet_after_expiry.available_balance
            subscription = SimpleNamespace(
                id=uuid4(),
                user_id=user.id,
                current_period_start=datetime(2026, 8, 1, tzinfo=UTC),
                current_period_end=datetime(2026, 9, 1, tzinfo=UTC),
                plan=SimpleNamespace(monthly_credit_grant=50, code="PRO"),
            )
            first = await service.grant_plan_period(subscription)
            duplicate = await service.grant_plan_period(subscription)
            expiration_count = await session.scalar(
                select(func.count())
                .select_from(CreditTransaction)
                .where(CreditTransaction.type == CreditTransactionType.EXPIRATION)
            )
            return balance_after_expiry, first.id == duplicate.id, expiration_count

    balance, same_grant, expiration_count = asyncio.run(exercise())
    assert balance == 100
    assert same_grant
    assert expiration_count == 1


def test_release_and_settlement_are_idempotent(
    client: TestClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    auth(client, "credit-idempotency@example.com")

    async def exercise() -> tuple[ReservationStatus, ReservationStatus, int, dict[str, object] | None]:
        async with session_factory() as session:
            user = await session.scalar(select(User).where(User.email == "credit-idempotency@example.com"))
            service = CreditService(session)
            released = await service.reserve(
                user.id, CreditOperationType.PROMPT_OPTIMIZATION, "openai", None, 0, 0, "release-once"
            )
            await service.release(released.id)
            released_again = await service.release(released.id)
            settled = await service.reserve(
                user.id, CreditOperationType.PROMPT_OPTIMIZATION, "openai", None, 0, 20, "settle-once"
            )
            await service.settle(
                settled.id,
                "openai",
                None,
                10,
                5,
                effective_provider="openai",
                effective_model="gpt-5.6-luna",
            )
            settled_again = await service.settle(settled.id, "openai", None, 10, 5)
            settlement_count = await session.scalar(
                select(func.count())
                .select_from(CreditTransaction)
                .where(CreditTransaction.idempotency_key == f"settlement:{settled.id}")
            )
            settlement_metadata = await session.scalar(
                select(CreditTransaction.transaction_metadata).where(
                    CreditTransaction.idempotency_key == f"settlement:{settled.id}"
                )
            )
            return released_again.status, settled_again.status, settlement_count, settlement_metadata

    released_status, settled_status, settlement_count, settlement_metadata = asyncio.run(exercise())
    assert released_status == ReservationStatus.RELEASED
    assert settled_status == ReservationStatus.SETTLED
    assert settlement_count == 1
    assert settlement_metadata is not None
    assert settlement_metadata["provider"] == "openai"
    assert settlement_metadata["model"] == "gpt-5.6-luna"


def test_admin_manages_packages_and_cost_rules(
    client: TestClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    headers = auth(client, "credits-manager@example.com")
    package_payload = {
        "code": "CREDITS_ADMIN_TEST",
        "name": "Admin Test",
        "credits": 250,
        "price": "9.90",
        "currency": "BRL",
        "bonus_credits": 10,
    }
    assert client.post("/api/v1/credits/packages", headers=headers, json=package_payload).status_code == 403

    async def promote() -> None:
        async with session_factory() as session:
            admin = await session.scalar(select(User).where(User.email == "credits-manager@example.com"))
            admin.role = Role.ADMIN
            await session.commit()

    asyncio.run(promote())
    package = client.post("/api/v1/credits/packages", headers=headers, json=package_payload)
    assert package.status_code == 201, package.text
    updated = client.patch(
        f"/api/v1/credits/packages/{package.json()['id']}", headers=headers, json={"is_active": False}
    )
    assert updated.status_code == 200 and updated.json()["is_active"] is False

    rule = client.post(
        "/api/v1/credits/costs",
        headers=headers,
        json={
            "operation_type": "image_generation",
            "provider": "future-provider",
            "base_credit_cost": 10,
            "input_token_rate": "0",
            "output_token_rate": "0",
            "minimum_credit_cost": 10,
        },
    )
    assert rule.status_code == 201, rule.text
    rule_update = client.patch(
        f"/api/v1/credits/costs/{rule.json()['id']}",
        headers=headers,
        json={"minimum_credit_cost": 12},
    )
    assert rule_update.status_code == 200
