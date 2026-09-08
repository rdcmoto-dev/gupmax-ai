import pytest
from fastapi.testclient import TestClient

from app.modules.projects import service as project_service


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Duplicate User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def create_project(client: TestClient, headers: dict[str, str], context: str) -> dict:
    response = client.post(
        "/api/v1/projects",
        headers=headers,
        json={
            "name": "Projeto <script>alert('dado')</script>",
            "description": "Descrição reutilizável",
            "context": context,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_duplicate_project_copies_reusable_structure_and_resets_state(client: TestClient) -> None:
    owner = auth(client, "duplicate-owner@example.com")
    context = (
        "Objetivo: Lançar campanha\n"
        "Critério de sucesso: [x] Campanha pronta\n"
        "Marco: [x] Publicar campanha\n"
        "Público: <script>alert('dado')</script>\n"
        "Conclusão do projeto: Trabalho finalizado\n"
        "Projeto encerrado: sim"
    )
    source = create_project(client, owner, context)
    chain = client.post(
        "/api/v1/chains",
        headers=owner,
        json={"name": "Fluxo reutilizável", "description": "Estrutura base", "project_id": source["id"]},
    ).json()
    first = client.post(
        f"/api/v1/chains/{chain['id']}/steps",
        headers=owner,
        json={
            "title": "Planejar",
            "base_input": "Planeje literalmente: <b>não execute</b>",
            "mode": "basic",
            "category": "marketing",
            "target_ai": "chatgpt",
        },
    ).json()
    client.post(
        f"/api/v1/chains/{chain['id']}/steps",
        headers=owner,
        json={
            "title": "Publicar",
            "base_input": "Use {resultado_anterior} como contexto",
            "mode": "pro",
            "category": "marketing",
            "target_ai": "gemini",
        },
    )
    assert client.post(f"/api/v1/chains/{chain['id']}/execution/start", headers=owner).status_code == 200
    assert client.put(
        f"/api/v1/chains/{chain['id']}/steps/{first['id']}/complete",
        headers=owner,
        json={"result": "Resultado histórico que não deve ser copiado"},
    ).status_code == 200
    generated = client.post(
        "/api/v1/prompts/generate",
        headers=owner,
        json={
            "project_id": source["id"],
            "input": "Prompt histórico",
            "category": "marketing",
            "mode": "basic",
            "optimize_with_ai": False,
        },
    )
    assert generated.status_code == 201
    source_before = client.get(f"/api/v1/projects/{source['id']}", headers=owner).json()
    chain_before = client.get(f"/api/v1/chains/{chain['id']}", headers=owner).json()

    response = client.post(
        f"/api/v1/projects/{source['id']}/duplicate",
        headers=owner,
        json={"name": "  Nova campanha segura  "},
    )
    assert response.status_code == 201, response.text
    duplicate = response.json()
    assert duplicate["id"] != source["id"]
    assert duplicate["name"] == "Nova campanha segura"
    assert duplicate["description"] == source["description"]
    assert duplicate["status"] == "active"
    assert duplicate["prompt_count"] == 0
    assert duplicate["context"] == (
        "Objetivo: Lançar campanha\n"
        "Critério de sucesso: Campanha pronta\n"
        "Marco: Publicar campanha\n"
        "Público: <script>alert('dado')</script>"
    )

    library = client.get(f"/api/v1/projects/{duplicate['id']}/library", headers=owner).json()
    assert library["prompt_total"] == 0
    assert len(library["chains"]) == 1
    duplicate_chain = client.get(f"/api/v1/chains/{library['chains'][0]['id']}", headers=owner).json()
    assert duplicate_chain["id"] != chain["id"]
    assert duplicate_chain["completed_step_count"] == 0
    assert duplicate_chain["current_step_id"] == duplicate_chain["steps"][0]["id"]
    assert [step["execution_status"] for step in duplicate_chain["steps"]] == ["pending", "pending"]
    assert all(step["result"] is None for step in duplicate_chain["steps"])
    assert [step["id"] for step in duplicate_chain["steps"]] != [
        step["id"] for step in chain_before["steps"]
    ]
    assert duplicate_chain["steps"][0]["base_input"] == "Planeje literalmente: <b>não execute</b>"
    assert duplicate_chain["steps"][1]["base_input"] == "Use {resultado_anterior} como contexto"
    assert client.get(f"/api/v1/projects/{source['id']}", headers=owner).json() == source_before
    assert client.get(f"/api/v1/chains/{chain['id']}", headers=owner).json() == chain_before


def test_duplicate_project_enforces_validation_ownership_and_fresh_owner(client: TestClient) -> None:
    owner = auth(client, "duplicate-security-owner@example.com")
    stranger = auth(client, "duplicate-security-stranger@example.com")
    source = create_project(client, owner, "Canal: Instagram")

    assert client.post(
        f"/api/v1/projects/{source['id']}/duplicate",
        headers=stranger,
        json={"name": "Cópia indevida"},
    ).status_code == 404
    assert client.post(
        f"/api/v1/projects/{source['id']}/duplicate", headers=owner, json={"name": "x"}
    ).status_code == 422
    assert client.post(
        f"/api/v1/projects/{source['id']}/duplicate", headers=owner, json={"name": "   "}
    ).status_code == 422
    assert client.post(
        f"/api/v1/projects/{source['id']}/duplicate",
        headers=owner,
        json={"name": "x" * 161, "user_id": "00000000-0000-0000-0000-000000000000"},
    ).status_code == 422

    duplicate = client.post(
        f"/api/v1/projects/{source['id']}/duplicate",
        headers=owner,
        json={"name": "Cópia válida"},
    )
    assert duplicate.status_code == 201
    assert client.get(f"/api/v1/projects/{duplicate.json()['id']}", headers=stranger).status_code == 404


def test_duplicate_project_rolls_back_everything_when_step_copy_fails(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    owner = auth(client, "duplicate-rollback@example.com")
    source = create_project(client, owner, "Objetivo: Preservar original")
    chain = client.post(
        "/api/v1/chains",
        headers=owner,
        json={"name": "Fluxo", "project_id": source["id"]},
    ).json()
    assert client.post(
        f"/api/v1/chains/{chain['id']}/steps",
        headers=owner,
        json={
            "title": "Etapa",
            "base_input": "Conteúdo",
            "mode": "basic",
            "category": "geral",
            "target_ai": "chatgpt",
        },
    ).status_code == 201
    before = client.get("/api/v1/projects", headers=owner, params={"include_archived": True}).json()

    def fail_step_copy(**_: object) -> None:
        raise RuntimeError("simulated copy failure")

    monkeypatch.setattr(project_service, "PromptChainStep", fail_step_copy)
    with pytest.raises(RuntimeError, match="simulated copy failure"):
        client.post(
            f"/api/v1/projects/{source['id']}/duplicate",
            headers=owner,
            json={"name": "Cópia parcial proibida"},
        )

    after = client.get("/api/v1/projects", headers=owner, params={"include_archived": True}).json()
    assert after == before
    assert client.get(f"/api/v1/projects/{source['id']}", headers=owner).status_code == 200
