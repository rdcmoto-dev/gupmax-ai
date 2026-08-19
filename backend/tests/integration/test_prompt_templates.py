import pytest
from fastapi.testclient import TestClient

from app.modules.prompt_engine.enums import PromptCategory, PromptMode


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Template User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def template_payload(**overrides):
    return {
        "name": "Campanha reutilizável",
        "description": "Base privada",
        "category": "marketing",
        "mode": "basic",
        "template_content": "## OBJECTIVE\nCriar uma campanha",
        "base_input": "Criar uma campanha",
        "language": "pt-BR",
        "tone": "casual",
        "audience": "clientes locais",
        "context": "Negócio local",
        "output_format": "lista curta",
        "constraints": ["Não invente dados"],
        "instructions": ["Seja objetivo"],
        "additional_information": "Canal/plataforma: TikTok",
        **overrides,
    }


def test_template_crud_ownership_and_delete_preserves_source(client: TestClient) -> None:
    owner = auth(client, "template-owner@example.com")
    other = auth(client, "template-other@example.com")
    prompt = client.post(
        "/api/v1/prompts/generate",
        headers=owner,
        json={"input": "Crie um anúncio para Instagram", "category": "marketing", "mode": "basic"},
    ).json()
    created = client.post(
        f"/api/v1/templates/from-prompt/{prompt['id']}",
        headers=owner,
        json={"name": "Anúncio Instagram", "description": "Versão escolhida"},
    )
    assert created.status_code == 201, created.text
    body = created.json()
    template_id = body["id"]
    assert body["source_prompt_id"] == prompt["id"]
    assert body["template_content"] == prompt["generated_prompt"]
    for excluded in ("provider", "model", "input_tokens", "output_tokens", "total_tokens", "idempotency_key"):
        assert excluded not in body
    assert client.get("/api/v1/templates", headers=owner).json()["total"] == 1
    assert client.get(f"/api/v1/templates/{template_id}", headers=other).status_code == 404
    assert client.put(
        f"/api/v1/templates/{template_id}", headers=other, json={"name": "Inválido"}
    ).status_code == 404
    assert client.delete(f"/api/v1/templates/{template_id}", headers=other).status_code == 404
    updated = client.put(
        f"/api/v1/templates/{template_id}",
        headers=owner,
        json={"name": "Campanha atualizada", "template_content": "Nova base reutilizável"},
    )
    assert updated.status_code == 200
    assert updated.json()["name"] == "Campanha atualizada"
    assert client.delete(f"/api/v1/templates/{template_id}", headers=owner).status_code == 204
    assert client.get(f"/api/v1/prompts/{prompt['id']}", headers=owner).status_code == 200


def test_specific_version_and_template_operations_have_no_financial_effect(client: TestClient) -> None:
    headers = auth(client, "template-version@example.com")
    original = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={"input": "Crie uma campanha para pizzaria", "category": "marketing", "mode": "basic"},
    ).json()
    refined = client.post(
        f"/api/v1/prompts/{original['id']}/refine",
        json={"instruction": "Deixe mais persuasivo", "optimize_with_ai": False},
        headers={**headers, "Idempotency-Key": "template-version-refine"},
    ).json()
    wallet_before = client.get("/api/v1/credits/wallet", headers=headers).json()
    usage_before = client.get("/api/v1/billing/usage", headers=headers).json()["total"]
    ledger_before = client.get("/api/v1/credits/transactions", headers=headers).json()["total"]
    saved = client.post(
        f"/api/v1/templates/from-prompt/{refined['id']}",
        headers=headers,
        json={"name": "Versão refinada"},
    ).json()
    assert saved["source_prompt_id"] == refined["id"]
    assert saved["template_content"] == refined["generated_prompt"]
    assert original["generated_prompt"] != saved["template_content"]
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == wallet_before
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == usage_before
    assert client.get("/api/v1/credits/transactions", headers=headers).json()["total"] == ledger_before


@pytest.mark.parametrize("category", [item.value for item in PromptCategory])
@pytest.mark.parametrize("mode", [item.value for item in PromptMode])
def test_templates_preserve_all_categories_and_modes(client: TestClient, category: str, mode: str) -> None:
    headers = auth(client, f"template-{category}-{mode}@example.com")
    response = client.post(
        "/api/v1/templates", headers=headers, json=template_payload(category=category, mode=mode)
    )
    assert response.status_code == 201, response.text
    assert response.json()["category"] == category
    assert response.json()["mode"] == mode


def test_template_values_beat_profile_and_local_override_beats_template(client: TestClient) -> None:
    headers = auth(client, "template-precedence@example.com")
    client.put(
        "/api/v1/profile/prompt-preferences",
        headers=headers,
        json={
            "is_enabled": True,
            "default_tone": "profissional",
            "default_channel": "Instagram",
        },
    )
    template = client.post("/api/v1/templates", headers=headers, json=template_payload()).json()
    base = {
        "input": template["base_input"],
        "category": template["category"],
        "mode": template["mode"],
        "tone": template["tone"],
        "additional_information": template["additional_information"],
        "optimize_with_ai": False,
    }
    generated = client.post("/api/v1/prompts/generate", headers=headers, json=base).json()["generated_prompt"]
    assert "casual" in generated and "TikTok" in generated
    assert "profissional" not in generated and "Instagram" not in generated
    override = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={**base, "tone": "persuasivo", "additional_information": "Canal/plataforma: YouTube"},
    ).json()["generated_prompt"]
    assert "persuasivo" in override and "YouTube" in override
    persisted = client.get(f"/api/v1/templates/{template['id']}", headers=headers).json()
    assert persisted["tone"] == "casual" and "TikTok" in persisted["additional_information"]


@pytest.mark.parametrize("mode", [item.value for item in PromptMode])
def test_current_form_overrides_facts_in_template_base_for_every_mode(
    client: TestClient, mode: str
) -> None:
    headers = auth(client, f"template-current-override-{mode}@example.com")
    template = client.post(
        "/api/v1/templates",
        headers=headers,
        json=template_payload(
            mode=mode,
            base_input="Crie um anúncio profissional para a pizzaria no Instagram.",
            tone="profissional",
            additional_information="Canal/plataforma: Instagram",
        ),
    ).json()
    wallet_before = client.get("/api/v1/credits/wallet", headers=headers).json()
    usage_before = client.get("/api/v1/billing/usage", headers=headers).json()["total"]
    ledger_before = client.get("/api/v1/credits/transactions", headers=headers).json()["total"]

    response = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "input": template["base_input"],
            "category": template["category"],
            "mode": template["mode"],
            "tone": "casual",
            "additional_information": "Canal/plataforma: TikTok",
            "optimize_with_ai": False,
        },
    )

    assert response.status_code == 201, response.text
    prompt = response.json()
    assert prompt["tone"] == "casual"
    assert "## TONE\ncasual" in prompt["generated_prompt"]
    assert "## ADDITIONAL INFORMATION\nCanal/plataforma: TikTok" in prompt["generated_prompt"]
    persisted = client.get(f"/api/v1/templates/{template['id']}", headers=headers).json()
    assert persisted["tone"] == "profissional"
    assert persisted["additional_information"] == "Canal/plataforma: Instagram"
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == wallet_before
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == usage_before
    assert client.get("/api/v1/credits/transactions", headers=headers).json()["total"] == ledger_before
