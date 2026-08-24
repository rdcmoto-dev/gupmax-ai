import pytest
from fastapi.testclient import TestClient

from app.modules.prompt_engine.enums import TargetAI


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Variables User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def create_template(client: TestClient, headers: dict[str, str], **overrides: object) -> dict[str, object]:
    payload = {
        "name": "Campanha dinâmica",
        "category": "marketing",
        "mode": "basic",
        "target_ai": "chatgpt",
        "template_content": "Crie uma campanha para {produto} voltada para {publico} no {canal}.",
        "base_input": "Crie uma campanha para {produto} voltada para {publico} no {canal}.",
        "language": "pt-BR",
        **overrides,
    }
    response = client.post("/api/v1/templates", headers=headers, json=payload)
    assert response.status_code == 201, response.text
    return response.json()


def resolved_payload(template_id: str, **overrides: object) -> dict[str, object]:
    return {
        "template_id": template_id,
        "input": "Placeholder válido para o contrato",
        "variable_values": {
            "produto": "Pizza artesanal",
            "publico": "Famílias da região",
            "canal": "Instagram",
        },
        "optimize_with_ai": False,
        **overrides,
    }


def test_template_contract_detects_and_resolves_without_mutating_original(client: TestClient) -> None:
    headers = auth(client, "dynamic-contract@example.com")
    template = create_template(client, headers)
    assert template["has_variables"] is True
    assert template["variables"] == [
        {"name": "produto", "label": "Produto", "required": True},
        {"name": "publico", "label": "Público", "required": True},
        {"name": "canal", "label": "Canal", "required": True},
    ]
    missing = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json=resolved_payload(template["id"], variable_values={"produto": "Pizza"}),
    )
    assert missing.status_code == 422
    assert missing.json()["detail"] == "Preencha Público."

    response = client.post("/api/v1/prompts/generate", headers=headers, json=resolved_payload(template["id"]))
    assert response.status_code == 201, response.text
    prompt = response.json()
    assert all(value in prompt["generated_prompt"] for value in ("Pizza artesanal", "Famílias", "Instagram"))
    assert "{produto}" not in prompt["generated_prompt"]
    score = client.get(f"/api/v1/prompts/{prompt['id']}/score", headers=headers)
    assert score.status_code == 200 and score.json()["score"] >= 0
    refined = client.post(
        f"/api/v1/prompts/{prompt['id']}/refine",
        headers={**headers, "Idempotency-Key": "dynamic-refine-v2"},
        json={"instruction": "Deixe mais curto.", "optimize_with_ai": False},
    )
    assert refined.status_code == 201, refined.text
    assert "Pizza artesanal" in refined.json()["generated_prompt"]
    assert "{produto}" not in refined.json()["generated_prompt"]
    versions = client.get(f"/api/v1/prompts/{refined.json()['id']}/versions", headers=headers).json()
    assert versions["total"] == 2
    persisted = client.get(f"/api/v1/templates/{template['id']}", headers=headers).json()
    assert persisted["base_input"] == template["base_input"]
    assert [variable["name"] for variable in persisted["variables"]] == [
        "produto",
        "publico",
        "canal",
    ]


def test_template_rejects_more_than_twenty_variables(client: TestClient) -> None:
    headers = auth(client, "dynamic-limit@example.com")
    content = " ".join(f"{{campo{index}}}" for index in range(21))
    response = client.post(
        "/api/v1/templates",
        headers=headers,
        json={
            "name": "Variáveis demais",
            "template_content": content,
            "base_input": content,
            "language": "pt-BR",
        },
    )
    assert response.status_code == 422

    valid = " ".join(f"{{campo{index}}}" for index in range(20))
    template = create_template(
        client,
        headers,
        template_content=valid,
        base_input=valid,
    )
    update = client.put(
        f"/api/v1/templates/{template['id']}",
        headers=headers,
        json={"template_content": content, "base_input": content},
    )
    assert update.status_code == 422


def test_legacy_template_and_variable_value_limits(client: TestClient) -> None:
    headers = auth(client, "dynamic-legacy@example.com")
    legacy = create_template(
        client,
        headers,
        template_content="Campanha literal reutilizável",
        base_input="Campanha literal reutilizável",
    )
    assert legacy["has_variables"] is False
    response = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "template_id": legacy["id"],
            "input": "Override local preservado",
            "optimize_with_ai": False,
        },
    )
    assert response.status_code == 201, response.text
    assert "Override local preservado" in response.json()["generated_prompt"]

    dynamic = create_template(
        client,
        headers,
        template_content="Crie para {produto}",
        base_input="Crie para {produto}",
    )
    too_long = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json=resolved_payload(dynamic["id"], variable_values={"produto": "á" * 4_001}),
    )
    assert too_long.status_code == 422


@pytest.mark.parametrize("target", [item.value for item in TargetAI])
def test_dynamic_template_supports_every_target(client: TestClient, target: str) -> None:
    headers = auth(client, f"dynamic-target-{target}@example.com")
    template = create_template(client, headers, target_ai=target)
    response = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json=resolved_payload(template["id"], target_ai=target),
    )
    assert response.status_code == 201, response.text
    assert response.json()["target_ai"] == target
    assert "Pizza artesanal" in response.json()["generated_prompt"]


def test_dynamic_template_ownership_project_target_and_compare_are_transient(client: TestClient) -> None:
    owner = auth(client, "dynamic-owner@example.com")
    stranger = auth(client, "dynamic-stranger@example.com")
    project = client.post(
        "/api/v1/projects", headers=owner, json={"name": "Donatello", "context": "Negócio regional"}
    ).json()
    template = create_template(client, owner)
    assert client.post(
        "/api/v1/prompts/generate", headers=stranger, json=resolved_payload(template["id"])
    ).status_code == 404
    before = client.get("/api/v1/prompts", headers=owner).json()["total"]
    compared = client.post(
        "/api/v1/prompts/compare-targets",
        headers=owner,
        json=resolved_payload(
            template["id"],
            project_id=project["id"],
            target_ais=["chatgpt", "claude", "gemini"],
        ),
    )
    assert compared.status_code == 200, compared.text
    assert [item["target_ai"] for item in compared.json()["items"]] == ["chatgpt", "claude", "gemini"]
    assert all("Pizza artesanal" in item["content"] for item in compared.json()["items"])
    assert client.get("/api/v1/prompts", headers=owner).json()["total"] == before


def test_variable_values_precede_project_and_smart_profile(client: TestClient) -> None:
    headers = auth(client, "dynamic-precedence@example.com")
    client.put(
        "/api/v1/profile/prompt-preferences",
        headers=headers,
        json={
            "is_enabled": True,
            "business_context": "Contexto do Smart Profile",
            "default_audience": "Público do Smart Profile",
            "default_channel": "Instagram",
        },
    )
    project = client.post(
        "/api/v1/projects",
        headers=headers,
        json={"name": "Projeto variável", "context": "Contexto exclusivo do Projeto"},
    ).json()
    content = "Crie para {produto}, {publico_alvo}, no {canal}. Contexto: {contexto}."
    template = create_template(
        client,
        headers,
        template_content=content,
        base_input=content,
    )
    response = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json=resolved_payload(
            template["id"],
            project_id=project["id"],
            variable_values={
                "produto": "Pizza",
                "publico_alvo": "Famílias",
                "canal": "TikTok",
                "contexto": "Campanha noturna",
            },
        ),
    )
    assert response.status_code == 201, response.text
    prompt = response.json()["generated_prompt"]
    assert all(value in prompt for value in ("Famílias", "TikTok", "Campanha noturna"))
    assert "Público do Smart Profile" not in prompt
    assert "Contexto exclusivo do Projeto" not in prompt
    assert "Contexto do Smart Profile" not in prompt


def test_dynamic_template_is_free_and_supports_interview_modes(client: TestClient) -> None:
    headers = auth(client, "dynamic-modes@example.com")
    wallet = client.get("/api/v1/credits/wallet", headers=headers).json()
    usage = client.get("/api/v1/billing/usage", headers=headers).json()["total"]
    ledger = client.get("/api/v1/credits/transactions", headers=headers).json()["total"]
    for mode in ("basic", "pro", "expert"):
        template = create_template(client, headers, name=f"Dinâmico {mode}", mode=mode)
        request = resolved_payload(template["id"], mode=mode)
        if mode == "basic":
            response = client.post("/api/v1/prompts/generate", headers=headers, json=request)
            assert response.status_code == 201, response.text
        else:
            interview = client.post(
                "/api/v1/interviews",
                headers=headers,
                json={
                    "initial_request": request["input"],
                    "mode": mode,
                    "category": "marketing",
                    "known_fields": request,
                },
            )
            assert interview.status_code == 201, interview.text
            current = interview.json()
            if current["questions"]:
                answers = []
                for question in current["questions"]:
                    value = (
                        question["options"][0]
                        if question["type"] == "single_choice"
                        else [question["options"][0]]
                        if question["type"] == "multi_choice"
                        else True
                        if question["type"] == "boolean"
                        else f"Resposta para {question['key']}"
                    )
                    answers.append({"question_key": question["key"], "value": value})
                answered = client.post(
                    f"/api/v1/interviews/{current['id']}/answers",
                    headers=headers,
                    json={"answers": answers},
                )
                assert answered.status_code == 200, answered.text
            completed = client.post(f"/api/v1/interviews/{current['id']}/complete", headers=headers)
            assert completed.status_code == 200, completed.text
            prompt_input = completed.json()["prompt_input"]
            assert prompt_input["template_id"] == template["id"]
            assert prompt_input["variable_values"]["produto"] == "Pizza artesanal"
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == wallet
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == usage
    assert client.get("/api/v1/credits/transactions", headers=headers).json()["total"] == ledger
