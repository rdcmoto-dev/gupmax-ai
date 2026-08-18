from fastapi.testclient import TestClient


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Score User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_score_endpoint_is_owned_repeatable_and_has_no_financial_side_effects(client: TestClient) -> None:
    owner = auth(client, "score-owner@example.com")
    stranger = auth(client, "score-stranger@example.com")
    created = client.post(
        "/api/v1/prompts/generate",
        headers=owner,
        json={"input": "Crie um anúncio para uma pizzaria.", "category": "marketing", "mode": "basic"},
    ).json()
    wallet_before = client.get("/api/v1/credits/wallet", headers=owner).json()
    usage_before = client.get("/api/v1/billing/usage", headers=owner).json()["total"]
    ledger_before = client.get("/api/v1/credits/transactions", headers=owner).json()["total"]

    first = client.get(f"/api/v1/prompts/{created['id']}/score", headers=owner)
    second = client.get(f"/api/v1/prompts/{created['id']}/score", headers=owner)

    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()
    assert first.json()["prompt_id"] == created["id"]
    assert len(first.json()["criteria"]) == 10
    assert client.get(f"/api/v1/prompts/{created['id']}/score", headers=stranger).status_code == 404
    assert client.get("/api/v1/credits/wallet", headers=owner).json() == wallet_before
    assert client.get("/api/v1/billing/usage", headers=owner).json()["total"] == usage_before
    assert client.get("/api/v1/credits/transactions", headers=owner).json()["total"] == ledger_before


def test_each_version_has_its_own_score(client: TestClient) -> None:
    headers = auth(client, "score-versions@example.com")
    source = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={"input": "Crie um anúncio.", "category": "marketing", "mode": "basic"},
    ).json()
    refined = client.post(
        f"/api/v1/prompts/{source['id']}/refine",
        headers={**headers, "Idempotency-Key": "score-refine-0001"},
        json={
            "instruction": "Defina Instagram, público de 18 a 35 anos, tom persuasivo e CTA para compra.",
            "optimize_with_ai": False,
        },
    ).json()
    old_score = client.get(f"/api/v1/prompts/{source['id']}/score", headers=headers).json()
    new_score = client.get(f"/api/v1/prompts/{refined['id']}/score", headers=headers).json()
    assert old_score["prompt_id"] != new_score["prompt_id"]
    assert 0 <= old_score["score"] <= 100
    assert 0 <= new_score["score"] <= 100
    assert new_score["score"] > old_score["score"]
