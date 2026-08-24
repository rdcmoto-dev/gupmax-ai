import pytest
from fastapi.testclient import TestClient

from app.modules.prompt_engine.enums import TargetAI


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Target User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


@pytest.mark.parametrize("target", [item.value for item in TargetAI])
def test_target_ai_is_persisted_returned_and_has_no_financial_side_effect(
    client: TestClient, target: str
) -> None:
    headers = auth(client, f"target-{target}@example.com")
    wallet_before = client.get("/api/v1/credits/wallet", headers=headers).json()
    usage_before = client.get("/api/v1/billing/usage", headers=headers).json()["total"]
    ledger_before = client.get("/api/v1/credits/transactions", headers=headers).json()["total"]
    created = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "input": "Crie uma campanha visual detalhada",
            "category": "marketing",
            "mode": "basic",
            "target_ai": target,
            "optimize_with_ai": False,
        },
    )
    assert created.status_code == 201, created.text
    prompt = created.json()
    assert prompt["target_ai"] == target
    assert client.get(f"/api/v1/prompts/{prompt['id']}", headers=headers).json()["target_ai"] == target
    assert client.get(f"/api/v1/prompts/{prompt['id']}/score", headers=headers).status_code == 200
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == wallet_before
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == usage_before
    assert client.get("/api/v1/credits/transactions", headers=headers).json()["total"] == ledger_before


def test_target_ai_defaults_validates_versions_templates_projects_and_ownership(client: TestClient) -> None:
    owner = auth(client, "target-owner@example.com")
    stranger = auth(client, "target-stranger@example.com")
    assert client.post("/api/v1/prompts/generate", headers=owner, json={"input": "Prompt legado"}).json()[
        "target_ai"
    ] == "generic"
    assert client.post(
        "/api/v1/prompts/generate", headers=owner, json={"input": "Prompt inválido", "target_ai": "invalid"}
    ).status_code == 422
    project = client.post("/api/v1/projects", headers=owner, json={"name": "Target project"}).json()
    source = client.post(
        "/api/v1/prompts/generate",
        headers=owner,
        json={"input": "Crie uma solução", "target_ai": "claude", "project_id": project["id"]},
    ).json()
    refined = client.post(
        f"/api/v1/prompts/{source['id']}/refine",
        headers={**owner, "Idempotency-Key": "target-refine"},
        json={"instruction": "Deixe mais curto"},
    ).json()
    assert refined["target_ai"] == "claude"
    versions = client.get(f"/api/v1/prompts/{refined['id']}/versions", headers=owner).json()["items"]
    assert [item["target_ai"] for item in versions] == ["claude", "claude"]
    saved = client.post(
        f"/api/v1/templates/from-prompt/{refined['id']}", headers=owner, json={"name": "Claude template"}
    ).json()
    assert saved["target_ai"] == "claude"
    assert client.get(f"/api/v1/prompts/{source['id']}", headers=stranger).status_code == 404


def test_midjourney_does_not_relabel_incompatible_smart_profile_fields(client: TestClient) -> None:
    headers = auth(client, "target-semantic-smoke@example.com")
    profile = {
        "is_enabled": True,
        "business_context": "Pequena empresa brasileira que vende produtos e serviços pela internet.",
        "default_audience": "donos de pequenos negócios",
        "default_tone": "profissional",
        "default_instructions": ["Priorize recomendações aplicáveis e objetivas."],
        "default_constraints": ["Use linguagem clara e prática."],
        "default_output_format": "lista objetiva",
        "default_channel": "Instagram",
    }
    saved = client.put("/api/v1/profile/prompt-preferences", headers=headers, json=profile)
    assert saved.status_code == 200, saved.text
    prompt = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "input": (
                "Criar uma imagem publicitária de uma pizza artesanal italiana sobre uma mesa de madeira, "
                "em uma pizzaria elegante."
            ),
            "category": "imagem",
            "mode": "basic",
            "target_ai": "midjourney",
            "optimize_with_ai": False,
        },
    )
    assert prompt.status_code == 201, prompt.text
    output = prompt.json()["generated_prompt"]
    assert "pizza artesanal italiana" in output
    assert "## ENVIRONMENT" in output
    assert "mesa de madeira" in output
    assert "pizzaria elegante" in output
    assert "## COMPOSITION" in output
    assert "## VISUAL STYLE" in output
    assert "## MOOD\nElegante" in output
    assert "## RELEVANT DETAILS" in output
    headings = [line for line in output.splitlines() if line.startswith("## ")]
    assert len(headings) == len(set(headings))
    for incompatible in (
        profile["business_context"], profile["default_audience"], profile["default_tone"],
        profile["default_instructions"][0], profile["default_constraints"][0],
        profile["default_output_format"], "Instagram",
    ):
        assert incompatible not in output
