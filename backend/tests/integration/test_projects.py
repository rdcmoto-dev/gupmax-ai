from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.modules.prompt_engine.enums import PromptMode


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Project User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def create_project(client: TestClient, headers: dict[str, str], **overrides):
    response = client.post(
        "/api/v1/projects",
        headers=headers,
        json={
            "name": "Pizzaria Donatello",
            "description": "Marketing e vendas",
            "context": "Pizzaria com delivery e atendimento no balcão.",
            **overrides,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def answer_value(question: dict[str, Any]) -> str | bool | list[str]:
    if question["type"] == "single_choice":
        return question["options"][0]
    if question["type"] == "multi_choice":
        return [question["options"][0]]
    if question["type"] == "boolean":
        return True
    return f"Resposta para {question['key']}"


def test_project_crud_archive_reactivate_and_idor(client: TestClient) -> None:
    owner = auth(client, "project-owner@example.com")
    other = auth(client, "project-other@example.com")
    project = create_project(client, owner)
    project_id = project["id"]
    assert project["status"] == "active"
    assert client.get("/api/v1/projects", headers=owner).json()["total"] == 1
    assert client.get(f"/api/v1/projects/{project_id}", headers=other).status_code == 404
    assert client.put(
        f"/api/v1/projects/{project_id}", headers=other, json={"name": "Inválido"}
    ).status_code == 404
    archived = client.put(
        f"/api/v1/projects/{project_id}", headers=owner, json={"status": "archived"}
    )
    assert archived.status_code == 200 and archived.json()["status"] == "archived"
    assert client.get("/api/v1/projects", headers=owner).json()["total"] == 0
    assert client.get(
        "/api/v1/projects", headers=owner, params={"include_archived": True}
    ).json()["total"] == 1
    reactivated = client.put(
        f"/api/v1/projects/{project_id}", headers=owner, json={"status": "active", "name": "Donatello"}
    )
    assert reactivated.json()["name"] == "Donatello"
    assert client.delete(f"/api/v1/projects/{project_id}", headers=other).status_code == 404


def test_associations_ownership_and_delete_preserve_content(client: TestClient) -> None:
    owner = auth(client, "project-association@example.com")
    other = auth(client, "project-association-other@example.com")
    project = create_project(client, owner)
    prompt = client.post(
        "/api/v1/prompts/generate",
        headers=owner,
        json={"input": "Crie uma campanha", "category": "marketing", "mode": "basic"},
    ).json()
    template = client.post(
        "/api/v1/templates",
        headers=owner,
        json={
            "name": "Campanha",
            "category": "marketing",
            "mode": "basic",
            "template_content": "## OBJECTIVE\nCriar campanha",
            "base_input": "Criar campanha",
        },
    ).json()
    project_id = project["id"]
    assert client.put(f"/api/v1/projects/{project_id}/prompts/{prompt['id']}", headers=other).status_code == 404
    assert client.put(f"/api/v1/projects/{project_id}/prompts/{prompt['id']}", headers=owner).status_code == 204
    assert client.put(f"/api/v1/projects/{project_id}/templates/{template['id']}", headers=owner).status_code == 204
    detail = client.get(f"/api/v1/projects/{project_id}", headers=owner).json()
    assert detail["prompt_count"] == 1 and detail["template_count"] == 1
    assert detail["prompts"][0]["project_id"] == project_id
    assert detail["templates"][0]["project_id"] == project_id
    assert client.delete(f"/api/v1/projects/{project_id}/prompts/{prompt['id']}", headers=owner).status_code == 204
    assert client.put(f"/api/v1/projects/{project_id}/prompts/{prompt['id']}", headers=owner).status_code == 204
    assert client.delete(f"/api/v1/projects/{project_id}", headers=owner).status_code == 204
    assert client.get(f"/api/v1/prompts/{prompt['id']}", headers=owner).json()["project_id"] is None
    assert client.get(f"/api/v1/templates/{template['id']}", headers=owner).json()["project_id"] is None


@pytest.mark.parametrize("mode", [item.value for item in PromptMode])
def test_project_context_precedence_modes_refinement_score_and_no_financial_effect(
    client: TestClient, mode: str
) -> None:
    headers = auth(client, f"project-precedence-{mode}@example.com")
    project = create_project(client, headers)
    client.put(
        "/api/v1/profile/prompt-preferences",
        headers=headers,
        json={
            "is_enabled": True,
            "business_context": "Pequena empresa brasileira que vende produtos e serviços pela internet.",
            "default_tone": "profissional",
        },
    )
    wallet = client.get("/api/v1/credits/wallet", headers=headers).json()
    usage = client.get("/api/v1/billing/usage", headers=headers).json()["total"]
    ledger = client.get("/api/v1/credits/transactions", headers=headers).json()["total"]

    project_fallback = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "project_id": project["id"], "input": "Crie uma campanha para aumentar vendas",
            "category": "marketing", "mode": mode, "optimize_with_ai": False, "context": None,
        },
    )
    assert project_fallback.status_code == 201, project_fallback.text
    body = project_fallback.json()
    assert project["context"] in body["generated_prompt"]
    assert "Pequena empresa brasileira que vende produtos e serviços pela internet." not in body["generated_prompt"]
    assert body["project_id"] == project["id"]

    template_context = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "project_id": project["id"], "input": "Crie campanha premium", "category": "marketing",
            "mode": mode, "context": "Campanha para pizzaria premium", "tone": "casual",
        },
    ).json()
    assert "Campanha para pizzaria premium" in template_context["generated_prompt"]
    assert "casual" in template_context["generated_prompt"]

    explicit = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "project_id": project["id"], "input": "Crie campanha", "category": "marketing", "mode": mode,
            "context": "Pizzaria focada em almoço executivo", "tone": "persuasivo",
        },
    ).json()
    assert "Pizzaria focada em almoço executivo" in explicit["generated_prompt"]
    assert "persuasivo" in explicit["generated_prompt"]
    refined = client.post(
        f"/api/v1/prompts/{explicit['id']}/refine", headers={**headers, "Idempotency-Key": f"project-{mode}-refine"},
        json={"instruction": "Deixe mais claro", "optimize_with_ai": False},
    ).json()
    assert refined["project_id"] == project["id"]
    assert client.get(f"/api/v1/prompts/{refined['id']}/score", headers=headers).status_code == 200
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == wallet
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == usage
    assert client.get("/api/v1/credits/transactions", headers=headers).json()["total"] == ledger


@pytest.mark.parametrize("mode", ["pro", "expert"])
def test_project_context_precedes_smart_profile_through_interview(
    client: TestClient, mode: str
) -> None:
    headers = auth(client, f"project-interview-precedence-{mode}@example.com")
    project = create_project(client, headers)
    profile_context = "Pequena empresa brasileira que vende produtos e serviços pela internet."
    client.put(
        "/api/v1/profile/prompt-preferences",
        headers=headers,
        json={"is_enabled": True, "business_context": profile_context},
    )
    start = client.post(
        "/api/v1/interviews",
        headers=headers,
        json={
            "initial_request": "Crie uma campanha para aumentar as vendas.",
            "mode": mode,
            "category": "marketing",
            "known_fields": {
                "project_id": project["id"],
                "input": "Crie uma campanha para aumentar as vendas.",
                "category": "marketing",
                "mode": mode,
                "context": None,
                "optimize_with_ai": False,
            },
        },
    )
    assert start.status_code == 201, start.text
    interview = start.json()
    required_answers = [
        {"question_key": question["key"], "value": answer_value(question)}
        for question in interview["questions"]
        if question["required"]
    ]
    if required_answers:
        answered = client.post(
            f"/api/v1/interviews/{interview['id']}/answers",
            headers=headers,
            json={"answers": required_answers},
        )
        assert answered.status_code == 200, answered.text
    completed = client.post(f"/api/v1/interviews/{interview['id']}/complete", headers=headers)
    assert completed.status_code == 200, completed.text
    prompt_input = completed.json()["prompt_input"]
    assert project["context"] in prompt_input["context"]
    assert profile_context not in prompt_input["context"]
    generated = client.post("/api/v1/prompts/generate", headers=headers, json=prompt_input)
    assert generated.status_code == 201, generated.text
    result = generated.json()
    assert project["context"] in result["generated_prompt"]
    assert profile_context not in result["generated_prompt"]
    assert result["project_id"] == project["id"]


@pytest.mark.parametrize("mode", [item.value for item in PromptMode])
def test_template_and_project_generate_single_structure(
    client: TestClient, mode: str
) -> None:
    headers = auth(client, f"project-template-structure-{mode}@example.com")
    project = create_project(
        client,
        headers,
        context="Pizzaria premium especializada em pizzas artesanais para eventos corporativos.",
    )
    profile_context = "Pequena empresa brasileira que vende produtos e serviços pela internet."
    client.put(
        "/api/v1/profile/prompt-preferences",
        headers=headers,
        json={"is_enabled": True, "business_context": profile_context},
    )
    objective = "Criar uma campanha para divulgar uma pizzaria"
    legacy_content = f"""## ROLE
Especialista em marketing e comunicação persuasiva

## OBJECTIVE
{objective}

## CONTEXT
{project["context"]}
## AUDIENCE
gestores de empresas

## INSTRUCTIONS
- Destaque os diferenciais

## CONSTRAINTS
- Não invente preços

## OUTPUT FORMAT
Título e texto curto

## LANGUAGE
pt-BR

## TONE
persuasivo

## ADDITIONAL INFORMATION
Canal/plataforma: LinkedIn"""
    template = client.post(
        "/api/v1/templates",
        headers=headers,
        json={
            "name": f"Campanha {mode}",
            "category": "marketing",
            "mode": mode,
            "template_content": legacy_content,
            "base_input": legacy_content,
            "language": "pt-BR",
            "tone": "persuasivo",
            "audience": "gestores de empresas",
            "instructions": ["Destaque os diferenciais"],
            "constraints": ["Não invente preços"],
            "output_format": "Título e texto curto",
            "additional_information": "Canal/plataforma: LinkedIn",
        },
    ).json()
    assert client.put(
        f"/api/v1/projects/{project['id']}/templates/{template['id']}", headers=headers
    ).status_code == 204
    original = client.get(f"/api/v1/templates/{template['id']}", headers=headers).json()
    response = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "project_id": project["id"],
            "input": template["base_input"],
            "category": template["category"],
            "mode": template["mode"],
            "language": template["language"],
            "tone": template["tone"],
            "audience": template["audience"],
            "context": template["context"],
            "instructions": template["instructions"],
            "constraints": template["constraints"],
            "output_format": template["output_format"],
            "additional_information": template["additional_information"],
            "optimize_with_ai": False,
        },
    )
    assert response.status_code == 201, response.text
    prompt = response.json()
    generated = prompt["generated_prompt"]
    sections = (
        "ROLE",
        "OBJECTIVE",
        "CONTEXT",
        "AUDIENCE",
        "INSTRUCTIONS",
        "CONSTRAINTS",
        "OUTPUT FORMAT",
        "LANGUAGE",
        "TONE",
        "ADDITIONAL INFORMATION",
    )
    assert all(generated.count(f"## {section}\n") == 1 for section in sections)
    assert not prompt["title"].startswith("## ROLE")
    assert prompt["title"] == objective
    assert project["context"] in generated
    assert profile_context not in generated
    assert client.get(f"/api/v1/templates/{template['id']}", headers=headers).json() == original
