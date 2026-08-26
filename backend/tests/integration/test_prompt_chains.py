from fastapi.testclient import TestClient


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Chain User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def create_chain(client: TestClient, headers: dict[str, str], **values: object) -> dict:
    response = client.post(
        "/api/v1/chains",
        headers=headers,
        json={"name": "Lançamento de pizzaria", "description": "Estratégia e campanha", **values},
    )
    assert response.status_code == 201, response.text
    return response.json()


def add_step(client: TestClient, headers: dict[str, str], chain_id: str, **values: object) -> dict:
    response = client.post(
        f"/api/v1/chains/{chain_id}/steps",
        headers=headers,
        json={
            "title": "Posicionamento",
            "base_input": "Crie posicionamento para {empresa}.",
            "mode": "basic",
            "category": "marketing",
            "target_ai": "chatgpt",
            **values,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_chain_crud_steps_reorder_archive_and_delete(client: TestClient) -> None:
    headers = auth(client, "chain-crud@example.com")
    chain = create_chain(client, headers)
    assert client.get("/api/v1/chains", headers=headers).json()["total"] == 1
    first = add_step(client, headers, chain["id"])
    second = add_step(
        client,
        headers,
        chain["id"],
        title="Campanha",
        base_input="Use {resultado_anterior} para criar campanha.",
        mode="pro",
        target_ai="claude",
    )
    detail = client.get(f"/api/v1/chains/{chain['id']}", headers=headers).json()
    assert detail["step_count"] == 2
    assert detail["steps"][0]["variables"][0]["name"] == "empresa"
    assert detail["steps"][1]["requires_previous_result"] is True

    updated = client.put(
        f"/api/v1/chains/{chain['id']}/steps/{first['id']}",
        headers=headers,
        json={"title": "Posicionamento da marca"},
    )
    assert updated.status_code == 200 and updated.json()["title"] == "Posicionamento da marca"
    reordered = client.put(
        f"/api/v1/chains/{chain['id']}/steps/reorder",
        headers=headers,
        json={"step_ids": [second["id"], first["id"]]},
    )
    assert reordered.status_code == 204
    assert client.get(f"/api/v1/chains/{chain['id']}", headers=headers).json()["steps"][0]["id"] == second["id"]

    assert client.put(
        f"/api/v1/chains/{chain['id']}", headers=headers, json={"status": "archived"}
    ).json()["status"] == "archived"
    assert client.put(
        f"/api/v1/chains/{chain['id']}", headers=headers, json={"status": "active"}
    ).json()["status"] == "active"
    assert client.delete(
        f"/api/v1/chains/{chain['id']}/steps/{second['id']}", headers=headers
    ).status_code == 204
    assert client.delete(f"/api/v1/chains/{chain['id']}", headers=headers).status_code == 204
    assert client.get(f"/api/v1/chains/{chain['id']}", headers=headers).status_code == 404


def test_chain_generation_previous_result_privacy_and_financial_invariants(client: TestClient) -> None:
    headers = auth(client, "chain-generate@example.com")
    project = client.post(
        "/api/v1/projects", headers=headers, json={"name": "Donatello", "context": "Pizzaria familiar"}
    ).json()
    chain = create_chain(client, headers, project_id=project["id"])
    first = add_step(client, headers, chain["id"])
    second = add_step(
        client,
        headers,
        chain["id"],
        title="Campanha",
        base_input=(
            "Com base no posicionamento anterior, crie uma campanha de lançamento para "
            "a {empresa} no Instagram: {resultado_anterior}"
        ),
        target_ai="chatgpt",
    )
    wallet = client.get("/api/v1/credits/wallet", headers=headers).json()
    usage = client.get("/api/v1/billing/usage", headers=headers).json()["total"]
    ledger = client.get("/api/v1/credits/transactions", headers=headers).json()["total"]
    generated = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "chain_id": chain["id"],
            "chain_step_id": first["id"],
            "input": first["base_input"],
            "variable_values": {"empresa": "Pizzaria Donatello"},
            "optimize_with_ai": False,
        },
    )
    assert generated.status_code == 201, generated.text
    assert "Pizzaria Donatello" in generated.json()["generated_prompt"]
    assert generated.json()["project_id"] == project["id"]
    missing = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={"chain_id": chain["id"], "chain_step_id": second["id"], "input": second["base_input"]},
    )
    assert missing.status_code == 422
    previous_objective = "Crie um posicionamento de marca para Pizzaria Donatello."
    previous = f"## OBJECTIVE\n{previous_objective}\n\n## CONTEXT\nNegócio familiar."
    result = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "chain_id": chain["id"],
            "chain_step_id": second["id"],
            "input": second["base_input"],
            "previous_result": previous,
            "variable_values": {"empresa": "Pizzaria Donatello"},
            "optimize_with_ai": False,
        },
    )
    assert result.status_code == 201, result.text
    content = result.json()["generated_prompt"]
    objective = content.split("## OBJECTIVE\n", 1)[1].split("\n\n##", 1)[0]
    assert "campanha de lançamento" in objective
    assert "Pizzaria Donatello" in objective
    assert previous_objective not in objective
    assert previous_objective in content
    assert "Negócio familiar." in content
    assert content.index(previous_objective) > content.index("PREVIOUS STEP RESULT (CONTEXT ONLY)")
    assert "{resultado_anterior}" not in content
    assert "{empresa}" not in result.json()["generated_prompt"]
    compared = client.post(
        "/api/v1/prompts/compare-targets",
        headers=headers,
        json={
            "chain_id": chain["id"],
            "chain_step_id": second["id"],
            "input": second["base_input"],
            "previous_result": previous,
            "variable_values": {"empresa": "Pizzaria Donatello"},
            "target_ais": ["chatgpt", "claude"],
            "optimize_with_ai": False,
        },
    )
    assert compared.status_code == 200, compared.text
    assert all(previous_objective in item["content"] for item in compared.json()["items"])
    assert all("campanha de lançamento" in item["content"] for item in compared.json()["items"])
    detail = client.get(f"/api/v1/chains/{chain['id']}", headers=headers).json()
    assert detail["steps"][1]["base_input"] == second["base_input"]
    assert previous not in str(detail)
    prompt_id = result.json()["id"]
    assert client.delete(f"/api/v1/chains/{chain['id']}", headers=headers).status_code == 204
    assert client.get(f"/api/v1/prompts/{prompt_id}", headers=headers).status_code == 200
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == wallet
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == usage
    assert client.get("/api/v1/credits/transactions", headers=headers).json()["total"] == ledger


def test_chain_project_template_ownership_and_step_limit(client: TestClient) -> None:
    owner = auth(client, "chain-owner@example.com")
    stranger = auth(client, "chain-stranger@example.com")
    project = client.post("/api/v1/projects", headers=owner, json={"name": "Private project"}).json()
    template = client.post(
        "/api/v1/templates",
        headers=owner,
        json={
            "name": "Template privado",
            "template_content": "Crie para {produto}",
            "base_input": "Crie para {produto}",
        },
    ).json()
    assert client.post(
        "/api/v1/chains", headers=stranger, json={"name": "Chain inválida", "project_id": project["id"]}
    ).status_code == 404
    chain = create_chain(client, owner)
    assert client.get(f"/api/v1/chains/{chain['id']}", headers=stranger).status_code == 404
    assert client.post(
        f"/api/v1/chains/{chain['id']}/steps",
        headers=stranger,
        json={"title": "Sem acesso", "base_input": "Prompt sem acesso"},
    ).status_code == 404
    first = add_step(client, owner, chain["id"], template_id=template["id"])
    assert first["template_id"] == template["id"]
    for index in range(1, 20):
        add_step(client, owner, chain["id"], title=f"Etapa número {index}", base_input=f"Prompt {index}")
    overflow = client.post(
        f"/api/v1/chains/{chain['id']}/steps",
        headers=owner,
        json={"title": "Etapa excedente", "base_input": "Prompt excedente"},
    )
    assert overflow.status_code == 422
