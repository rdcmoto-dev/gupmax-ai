import pytest
from fastapi.testclient import TestClient


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Compare User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def payload(targets: list[str], **overrides: object) -> dict[str, object]:
    return {
        "input": "Crie uma campanha para aumentar as vendas de uma pizzaria.",
        "category": "marketing",
        "mode": "basic",
        "target_ais": targets,
        "optimize_with_ai": False,
        **overrides,
    }


@pytest.mark.parametrize("mode", ["basic", "pro", "expert"])
@pytest.mark.parametrize(
    "targets",
    [
        ["chatgpt", "claude"],
        ["chatgpt", "claude", "gemini"],
        ["chatgpt", "claude", "gemini", "coding_assistant"],
    ],
)
def test_compare_two_to_four_targets_is_distinct_scored_and_not_persisted(
    client: TestClient, mode: str, targets: list[str]
) -> None:
    headers = auth(client, f"compare-{mode}-{len(targets)}@example.com")
    before = client.get("/api/v1/prompts", headers=headers).json()["total"]
    response = client.post("/api/v1/prompts/compare-targets", headers=headers, json=payload(targets, mode=mode))
    assert response.status_code == 200, response.text
    items = response.json()["items"]
    assert [item["target_ai"] for item in items] == targets
    assert len({item["content"] for item in items}) == len(targets)
    assert all(0 <= item["score"] <= 100 and item["rating"] for item in items)
    assert client.get("/api/v1/prompts", headers=headers).json()["total"] == before


@pytest.mark.parametrize(
    "targets",
    [
        ["chatgpt"],
        ["chatgpt", "claude", "gemini", "midjourney", "image_generator"],
        ["chatgpt", "chatgpt"],
        ["chatgpt", "invalid"],
    ],
)
def test_compare_validates_limits_duplicates_and_targets(client: TestClient, targets: list[str]) -> None:
    headers = auth(client, f"compare-invalid-{len(targets)}-{targets[-1]}@example.com")
    assert client.post(
        "/api/v1/prompts/compare-targets", headers=headers, json=payload(targets)
    ).status_code == 422


def test_compare_is_deterministic_free_and_saves_only_selected_version(client: TestClient) -> None:
    headers = auth(client, "compare-save@example.com")
    count_before = client.get("/api/v1/prompts", headers=headers).json()["total"]
    wallet = client.get("/api/v1/credits/wallet", headers=headers).json()
    usage = client.get("/api/v1/billing/usage", headers=headers).json()["total"]
    ledger = client.get("/api/v1/credits/transactions", headers=headers).json()["total"]
    compared = client.post(
        "/api/v1/prompts/compare-targets",
        headers=headers,
        json=payload(["chatgpt", "claude", "gemini"]),
    ).json()["items"]
    count_after_compare = client.get("/api/v1/prompts", headers=headers).json()["total"]
    assert count_after_compare == count_before
    selected = next(item for item in compared if item["target_ai"] == "gemini")
    saved = client.post(
        "/api/v1/prompts/generate",
        headers={**headers, "Idempotency-Key": "compare-save-gemini"},
        json=payload(["chatgpt", "claude"]) | {"target_ai": selected["target_ai"]},
    )
    assert saved.status_code == 201, saved.text
    assert saved.json()["target_ai"] == "gemini"
    history = client.get("/api/v1/prompts", headers=headers).json()
    assert history["total"] == count_before + 1
    assert [item["target_ai"] for item in history["items"]] == ["gemini"]
    assert not any(item["target_ai"] in {"chatgpt", "claude"} for item in history["items"])
    # Reabrir o histórico e atualizar a página são apenas GETs e não persistem previews.
    assert client.get("/api/v1/prompts", headers=headers).json()["total"] == count_before + 1
    assert client.get("/api/v1/prompts", headers=headers).json()["total"] == count_before + 1
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == wallet
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == usage
    assert client.get("/api/v1/credits/transactions", headers=headers).json()["total"] == ledger


def test_compare_preserves_specialized_targets_and_project_ownership(client: TestClient) -> None:
    owner = auth(client, "compare-project-owner@example.com")
    stranger = auth(client, "compare-project-stranger@example.com")
    project = client.post(
        "/api/v1/projects",
        headers=owner,
        json={"name": "Campanha visual", "context": "Pequena empresa brasileira que vende pela internet"},
    ).json()
    visual = client.post(
        "/api/v1/prompts/compare-targets",
        headers=owner,
        json=payload(
            ["midjourney", "image_generator"],
            input=(
                "Criar uma imagem publicitária de uma pizza artesanal italiana sobre uma mesa de madeira "
                "em uma pizzaria elegante."
            ),
            category="imagem",
            project_id=project["id"],
        ),
    )
    assert visual.status_code == 200, visual.text
    assert all("mesa de madeira" in item["content"] for item in visual.json()["items"])
    assert all("Pequena empresa brasileira" not in item["content"] for item in visual.json()["items"])
    video_coding = client.post(
        "/api/v1/prompts/compare-targets",
        headers=owner,
        json=payload(
            ["video_generator", "coding_assistant"],
            input=(
                "Criar um vídeo de 15 segundos mostrando uma pizza sendo preparada, saindo do forno "
                "e sendo servida em uma pizzaria elegante."
            ),
        ),
    ).json()["items"]
    assert "sendo preparada; saindo do forno; sendo servida" in video_coding[0]["content"]
    assert client.post(
        "/api/v1/prompts/compare-targets",
        headers=stranger,
        json=payload(["chatgpt", "claude"], project_id=project["id"]),
    ).status_code == 404


def test_compare_rejects_ai_optimization_and_requires_authentication(client: TestClient) -> None:
    assert client.post(
        "/api/v1/prompts/compare-targets", json=payload(["chatgpt", "claude"])
    ).status_code == 401
    headers = auth(client, "compare-ai-disabled@example.com")
    assert client.post(
        "/api/v1/prompts/compare-targets",
        headers=headers,
        json=payload(["chatgpt", "claude"], optimize_with_ai=True),
    ).status_code == 422
