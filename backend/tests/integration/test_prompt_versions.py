import asyncio
import re
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.main import app
from app.modules.ai_gateway.dependencies import get_ai_gateway_service
from app.modules.ai_gateway.schemas import GenerateTextResponse, TokenUsageResponse
from app.modules.credits.model import CreditTransaction
from app.modules.users.model import User


class RefinementGateway:
    def __init__(self, *, fail: bool = False) -> None:
        self.calls = 0
        self.fail = fail

    async def generate(self, data: Any) -> GenerateTextResponse:
        self.calls += 1
        if self.fail:
            raise RuntimeError("provider unavailable")
        user_prompt = data.user_prompt
        match = re.search(r"<untrusted_prompt>\n(.*?)\n</untrusted_prompt>", user_prompt, re.DOTALL)
        assert match is not None
        return GenerateTextResponse(
            provider="openai",
            model="gpt-5.6-luna",
            text=f"{match.group(1)}\n\n## REFINEMENT\n- Mais persuasivo e conciso.",
            latency_ms=1,
            usage=TokenUsageResponse(input_tokens=30, output_tokens=20, total_tokens=50),
        )


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Version User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def create_prompt(client: TestClient, headers: dict[str, str], *, mode: str = "basic") -> dict[str, object]:
    response = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "input": "Crie um anúncio para uma pizzaria no Instagram.",
            "mode": mode,
            "category": "marketing",
            "tone": "profissional",
            "context": "Promoção de pizza às sextas-feiras.",
            "audience": "Jovens adultos da região.",
            "constraints": ["Não invente preços."],
            "output_format": "Texto curto para rede social.",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.mark.parametrize("mode", ["basic", "pro", "expert"])
def test_deterministic_refinement_creates_version_and_preserves_source(client: TestClient, mode: str) -> None:
    headers = auth(client, f"versions-{mode}@example.com")
    source = create_prompt(client, headers, mode=mode)
    assert source["version_number"] == 1
    assert source["parent_prompt_id"] is None
    assert source["root_prompt_id"] is None
    detail = client.get(f"/api/v1/prompts/{source['id']}", headers=headers)
    assert detail.status_code == 200
    headers["Idempotency-Key"] = f"refine-{mode}-0001"
    payload = {"instruction": "Deixe mais persuasivo e mantenha curto.", "optimize_with_ai": False}

    first = client.post(f"/api/v1/prompts/{source['id']}/refine", headers=headers, json=payload)
    duplicate = client.post(f"/api/v1/prompts/{source['id']}/refine", headers=headers, json=payload)

    assert first.status_code == duplicate.status_code == 201
    refined = first.json()
    assert duplicate.json()["id"] == refined["id"]
    assert refined["parent_prompt_id"] == source["id"]
    assert refined["root_prompt_id"] == source["id"]
    assert refined["version_number"] == 2
    assert refined["mode"] == mode
    assert refined["tone"] == "persuasivo"
    assert "Instagram" in refined["generated_prompt"]
    assert "Mantenha a resposta concisa" in refined["generated_prompt"]
    assert client.get(f"/api/v1/prompts/{source['id']}", headers=headers).json()["generated_prompt"] == source[
        "generated_prompt"
    ]
    versions_response = client.get(f"/api/v1/prompts/{refined['id']}/versions", headers=headers)
    assert versions_response.status_code == 200
    versions = versions_response.json()
    assert versions["total"] == 2
    assert [item["version_number"] for item in versions["items"]] == [1, 2]


def test_refinement_validates_instruction_and_ownership(client: TestClient) -> None:
    owner = auth(client, "version-owner@example.com")
    stranger = auth(client, "version-stranger@example.com")
    source = create_prompt(client, owner)

    invalid = client.post(f"/api/v1/prompts/{source['id']}/refine", headers=owner, json={"instruction": " "})
    assert invalid.status_code == 422
    assert (
        client.post(
            f"/api/v1/prompts/{source['id']}/refine",
            headers=stranger,
            json={"instruction": "Deixe mais curto."},
        ).status_code
        == 404
    )
    assert client.get(f"/api/v1/prompts/{source['id']}/versions", headers=stranger).status_code == 404


def test_ai_refinement_reuses_usage_credits_ledger_and_idempotency(
    client: TestClient, session_factory: async_sessionmaker[AsyncSession]
) -> None:
    headers = auth(client, "version-ai@example.com")
    source = create_prompt(client, headers, mode="expert")
    headers["Idempotency-Key"] = "refine-ai-0001"
    gateway = RefinementGateway()
    app.dependency_overrides[get_ai_gateway_service] = lambda: gateway
    try:
        payload = {"instruction": "Deixe mais persuasivo e mantenha curto.", "optimize_with_ai": True}
        first = client.post(f"/api/v1/prompts/{source['id']}/refine", headers=headers, json=payload)
        duplicate = client.post(f"/api/v1/prompts/{source['id']}/refine", headers=headers, json=payload)
    finally:
        app.dependency_overrides.pop(get_ai_gateway_service, None)

    assert first.status_code == duplicate.status_code == 201, first.text
    assert first.json()["id"] == duplicate.json()["id"]
    assert first.json()["status"] == "optimized"
    assert first.json()["model"] == "gpt-5.6-luna"
    assert gateway.calls == 1
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == 1
    wallet = client.get("/api/v1/credits/wallet", headers=headers).json()
    assert wallet["available_balance"] < 100
    assert wallet["reserved_balance"] == 0
    ledger = client.get("/api/v1/credits/transactions", headers=headers).json()["items"]

    async def purposes() -> set[str]:
        async with session_factory() as session:
            user = await session.scalar(select(User).where(User.email == "version-ai@example.com"))
            transactions = (
                await session.scalars(select(CreditTransaction).where(CreditTransaction.user_id == user.id))
            ).all()
            return {
                str(item.type)
                for item in transactions
                if (item.transaction_metadata or {}).get("purpose") == "prompt_refinement"
            }

    assert asyncio.run(purposes()) >= {"reservation", "ai_usage"}
    assert len([item for item in ledger if item["type"] == "ai_usage"]) == 1


def test_failed_ai_refinement_releases_and_does_not_create_version(client: TestClient) -> None:
    headers = auth(client, "version-ai-failure@example.com")
    source = create_prompt(client, headers)
    gateway = RefinementGateway(fail=True)
    app.dependency_overrides[get_ai_gateway_service] = lambda: gateway
    try:
        with pytest.raises(RuntimeError):
            client.post(
                f"/api/v1/prompts/{source['id']}/refine",
                headers=headers,
                json={"instruction": "Deixe mais curto.", "optimize_with_ai": True},
            )
    finally:
        app.dependency_overrides.pop(get_ai_gateway_service, None)

    assert client.get(f"/api/v1/prompts/{source['id']}/versions", headers=headers).json()["total"] == 1
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == 0
    assert client.get("/api/v1/credits/wallet", headers=headers).json()["reserved_balance"] == 0
    ledger = client.get("/api/v1/credits/transactions", headers=headers).json()["items"]
    assert any(item["type"] == "reservation_release" for item in ledger)
