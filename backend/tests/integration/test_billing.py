import asyncio
from datetime import UTC, datetime, timedelta

from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.main import app
from app.modules.ai_gateway.dependencies import get_ai_gateway_service
from app.modules.ai_gateway.schemas import GenerateTextResponse, TokenUsageResponse
from app.modules.billing.model import Plan, Subscription
from app.modules.users.model import User
from app.modules.users.roles import Role


class FakeGateway:
    async def generate(self, _data: object) -> GenerateTextResponse:
        return GenerateTextResponse(
            provider="fake",
            model="fake-model",
            text="PROMPT OTIMIZADO",
            latency_ms=1,
            usage=TokenUsageResponse(input_tokens=12, output_tokens=5, total_tokens=17),
        )


def _auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Billing User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _prompt(client: TestClient, headers: dict[str, str], optimize: bool):
    return client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={"input": "Crie uma campanha profissional", "optimize_with_ai": optimize},
    )


def test_billing_endpoints_require_authentication(client: TestClient) -> None:
    for path in ("plans", "subscription", "usage", "limits"):
        assert client.get(f"/api/v1/billing/{path}").status_code == 401


def test_trial_plans_subscription_and_initial_limits(client: TestClient) -> None:
    headers = _auth(client, "billing@example.com")
    plans = client.get("/api/v1/billing/plans", headers=headers)
    assert plans.status_code == 200
    assert [item["code"] for item in plans.json()] == ["FREE", "STARTER", "PRO", "BUSINESS"]

    subscription = client.get("/api/v1/billing/subscription", headers=headers)
    assert subscription.status_code == 200
    assert subscription.json()["plan"]["code"] == "STARTER"
    assert subscription.json()["status"] == "trialing"
    assert subscription.json()["trial_status"] == "active"

    limits = client.get("/api/v1/billing/limits", headers=headers).json()
    assert limits["generations"] == {"used": 0, "limit": 100, "remaining": 100}
    assert limits["trial"] == "active"


def test_common_user_cannot_manage_plans(client: TestClient) -> None:
    headers = _auth(client, "forbidden@example.com")
    response = client.post(
        "/api/v1/billing/plans",
        headers=headers,
        json={
            "code": "CUSTOM",
            "name": "Custom",
            "description": "Custom",
            "price": "10.00",
            "currency": "BRL",
            "billing_interval": "month",
            "trial_days": 0,
            "monthly_generation_limit": 10,
            "monthly_input_token_limit": 1000,
            "monthly_output_token_limit": 1000,
        },
    )
    assert response.status_code == 403


def test_admin_can_create_update_and_deactivate_plan(
    client: TestClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    headers = _auth(client, "admin-billing@example.com")

    async def promote() -> None:
        async with session_factory() as session:
            user = await session.scalar(select(User).where(User.email == "admin-billing@example.com"))
            assert user is not None
            user.role = Role.ADMIN
            await session.commit()

    asyncio.run(promote())
    created = client.post(
        "/api/v1/billing/plans",
        headers=headers,
        json={
            "code": "CUSTOM",
            "name": "Custom",
            "description": "Custom",
            "price": "10.00",
            "currency": "BRL",
            "billing_interval": "month",
            "trial_days": 0,
            "monthly_generation_limit": 10,
            "monthly_input_token_limit": 1000,
            "monthly_output_token_limit": 1000,
        },
    )
    assert created.status_code == 201, created.text
    plan_id = created.json()["id"]
    updated = client.patch(
        f"/api/v1/billing/plans/{plan_id}", headers=headers, json={"price": "12.50", "is_active": False}
    )
    assert updated.status_code == 200
    assert updated.json()["price"] == "12.50"
    assert updated.json()["is_active"] is False


def test_deterministic_generation_is_free_and_ai_usage_is_recorded(client: TestClient) -> None:
    headers = _auth(client, "usage@example.com")
    assert _prompt(client, headers, False).status_code == 201
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == 0

    app.dependency_overrides[get_ai_gateway_service] = lambda: FakeGateway()
    try:
        optimized = _prompt(client, headers, True)
    finally:
        app.dependency_overrides.pop(get_ai_gateway_service, None)
    assert optimized.status_code == 201, optimized.text
    usage = client.get("/api/v1/billing/usage", headers=headers).json()
    assert usage["total"] == 1
    assert usage["items"][0]["generation_count"] == 1
    assert usage["items"][0]["total_tokens"] == 17
    limits = client.get("/api/v1/billing/limits", headers=headers).json()
    assert limits["generations"]["used"] == 1
    assert limits["input_tokens"]["used"] == 12


def test_expired_trial_blocks_before_gateway(
    client: TestClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    headers = _auth(client, "expired@example.com")

    async def expire() -> None:
        async with session_factory() as session:
            user_id = await session.scalar(select(User.id).where(User.email == "expired@example.com"))
            subscription = await session.scalar(select(Subscription).where(Subscription.user_id == user_id))
            assert subscription is not None
            subscription.trial_ends_at = datetime.now(UTC) - timedelta(days=1)
            await session.commit()

    asyncio.run(expire())
    app.dependency_overrides[get_ai_gateway_service] = lambda: FakeGateway()
    try:
        response = _prompt(client, headers, True)
    finally:
        app.dependency_overrides.pop(get_ai_gateway_service, None)
    assert response.status_code == 403
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == 0


def test_generation_limit_blocks_before_gateway(
    client: TestClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    headers = _auth(client, "limited@example.com")

    async def remove_capacity() -> None:
        async with session_factory() as session:
            plan = await session.scalar(select(Plan).where(Plan.code == "STARTER"))
            assert plan is not None
            plan.monthly_generation_limit = 0
            await session.commit()

    asyncio.run(remove_capacity())
    app.dependency_overrides[get_ai_gateway_service] = lambda: FakeGateway()
    try:
        response = _prompt(client, headers, True)
    finally:
        app.dependency_overrides.pop(get_ai_gateway_service, None)
    assert response.status_code == 429
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == 0
