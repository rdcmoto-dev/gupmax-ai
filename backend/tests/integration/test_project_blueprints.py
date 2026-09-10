from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.db.base import Base
from app.modules.ai_gateway.service import AIGatewayService
from app.modules.project_blueprints import service

ROOT = "/api/v1/project-blueprints"


def auth(client: TestClient, email: str = "blueprints@example.com") -> dict:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "full_name": "Blueprint User",
            "password": "SecurePassword123!",
        },
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def source(client: TestClient, owner: dict) -> dict:
    response = client.post(
        "/api/v1/projects",
        headers=owner,
        json={
            "name": "Projeto original",
            "description": "Descrição original",
            "context": "Objetivo: Publicar\nCritério de sucesso: [x] Material pronto\nMarco: [x] Publicado\n"
            "Público: <script>literal</script>\nConclusão do projeto: Entregue\nProjeto encerrado: sim\n"
            "resultado_anterior: histórico operacional",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def save(client: TestClient, owner: dict, project: dict) -> dict:
    response = client.post(
        ROOT,
        headers=owner,
        json={
            "source_project_id": project["id"],
            "name": "Modelo reutilizável",
            "description": "Catálogo pessoal",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


async def snapshot(factory: async_sessionmaker[AsyncSession]) -> dict:
    async with factory() as session:
        return {
            table.name: [
                dict(row)
                for row in (await session.execute(select(table).order_by(*table.primary_key.columns))).mappings()
            ]
            for table in Base.metadata.sorted_tables
        }


def test_blueprint_clean_structure_independence_and_zero_operational_writes(
    client: TestClient,
    session_factory: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    owner = auth(client)
    project = source(client, owner)
    path = f"/api/v1/projects/{project['id']}"
    chain = client.post(
        "/api/v1/chains", headers=owner, json={"name": "Fluxo base", "project_id": project["id"]}
    ).json()
    chain_path = f"/api/v1/chains/{chain['id']}"
    first = client.post(
        chain_path + "/steps",
        headers=owner,
        json={
            "title": "Planejar",
            "base_input": "Planeje {produto}",
            "mode": "expert",
            "category": "marketing",
            "target_ai": "claude",
        },
    ).json()
    assert (
        client.post(
            chain_path + "/steps",
            headers=owner,
            json={
                "title": "Executar",
                "base_input": "Use {resultado_anterior}",
                "mode": "pro",
                "category": "marketing",
                "target_ai": "gemini",
            },
        ).status_code
        == 201
    )
    assert client.post(chain_path + "/execution/start", headers=owner).status_code == 200
    assert (
        client.put(
            chain_path + f"/steps/{first['id']}/complete",
            headers=owner,
            json={"result": "Histórico que não pode ser copiado"},
        ).status_code
        == 200
    )
    prompt = client.post(
        "/api/v1/prompts/generate",
        headers=owner,
        json={
            "project_id": project["id"],
            "input": "Campanha original",
            "mode": "basic",
            "category": "marketing",
            "optimize_with_ai": False,
        },
    ).json()
    assert (
        client.post(
            f"/api/v1/prompts/{prompt['id']}/refine",
            headers=owner,
            json={
                "instruction": "Deixe mais curto",
                "optimize_with_ai": False,
            },
        ).status_code
        == 201
    )
    assert client.put(path, headers=owner, json={"status": "archived"}).status_code == 200
    assert client.put(path + "/favorite", headers=owner, json={"is_favorite": True}).status_code == 200
    template = client.post(
        "/api/v1/templates",
        headers=owner,
        json={
            "name": "Template intacto",
            "template_content": "Texto original",
            "base_input": "Base original",
        },
    ).json()
    assert client.put(path + f"/templates/{template['id']}", headers=owner).status_code == 204

    async def forbidden(*args: object, **kwargs: object) -> None:
        pytest.fail("Blueprint operation must not invoke AI")

    monkeypatch.setattr(AIGatewayService, "generate", forbidden)
    monkeypatch.setattr(AIGatewayService, "stream", forbidden)
    before = client.portal.call(snapshot, session_factory)
    blueprint = save(client, owner, project)
    structure = blueprint["structure"]
    assert structure["objective"] == "Publicar"
    assert structure["success_criteria"] == ["Material pronto"]
    assert structure["milestones"] == ["Publicado"]
    assert structure["context"] == "Público: <script>literal</script>"
    assert blueprint["category"] == "marketing"
    assert set(structure) == {
        "version",
        "project_name",
        "description",
        "objective",
        "success_criteria",
        "milestones",
        "context",
        "chains",
    }
    assert set(structure["chains"][0]) == {"name", "description", "steps"}
    assert set(structure["chains"][0]["steps"][0]) == {"title", "base_input", "mode", "category", "target_ai"}
    assert structure["chains"][0]["steps"][1]["base_input"] == "Use {resultado_anterior}"
    after_save = client.portal.call(snapshot, session_factory)
    assert {k: v for k, v in after_save.items() if k != "project_blueprints"} == {
        k: v for k, v in before.items() if k != "project_blueprints"
    }
    created = client.post(ROOT + f"/{blueprint['id']}/projects", headers=owner, json={"name": "Novo independente"})
    assert created.status_code == 201, created.text
    new = created.json()
    assert new["id"] != project["id"]
    assert new["status"] == "active" and new["is_favorite"] is False
    assert new["prompt_count"] == new["template_count"] == 0
    assert (
        new["context"]
        == "Objetivo: Publicar\nCritério de sucesso: Material pronto\n"
        "Marco: Publicado\nPúblico: <script>literal</script>"
    )
    library = client.get(f"/api/v1/projects/{new['id']}/library", headers=owner).json()
    new_chain = client.get(f"/api/v1/chains/{library['chains'][0]['id']}", headers=owner).json()
    assert new_chain["id"] != chain["id"] and new_chain["status"] == "active"
    assert new_chain["completed_step_count"] == 0
    for step in new_chain["steps"]:
        assert step["execution_status"] == "pending"
        assert step["result"] is step["started_at"] is step["completed_at"] is None
    assert new_chain["steps"][0]["target_ai"] == "claude"
    assert new_chain["steps"][1]["target_ai"] == "gemini"
    after_use = client.portal.call(snapshot, session_factory)
    for table, rows in after_save.items():
        if table in {"projects", "prompt_chains", "prompt_chain_steps"}:
            assert all(row in after_use[table] for row in rows)
        else:
            assert after_use[table] == rows
    assert client.get(ROOT + f"/{blueprint['id']}", headers=owner).json() == blueprint
    assert client.delete(path, headers=owner).status_code == 204
    assert (
        client.post(ROOT + f"/{blueprint['id']}/projects", headers=owner, json={"name": "Uso sem original"}).status_code
        == 201
    )


def test_blueprint_edit_delete_and_projects_remain_independent(client: TestClient) -> None:
    owner = auth(client)
    blueprint = save(client, owner, source(client, owner))
    path = ROOT + f"/{blueprint['id']}"
    new = client.post(path + "/projects", headers=owner, json={"name": "Projeto preservado"}).json()
    before = client.get(f"/api/v1/projects/{new['id']}", headers=owner).json()
    response = client.put(
        path, headers=owner, json={"name": "Modelo editado", "description": "Nova descrição", "category": "vendas"}
    )
    assert response.status_code == 200
    edited = client.get(path, headers=owner).json()
    assert edited["name"] == "Modelo editado" and edited["category"] == "vendas"
    assert edited["description"] == "Nova descrição" and edited["structure"] == blueprint["structure"]
    assert client.delete(path, headers=owner).status_code == 204
    assert client.get(path, headers=owner).status_code == 404
    assert client.get(ROOT, headers=owner).json()["total"] == 0
    assert client.get(f"/api/v1/projects/{new['id']}", headers=owner).json() == before


def test_blueprint_all_ownership_paths_and_client_ownership_rejected(client: TestClient) -> None:
    owner = auth(client)
    other = auth(client, "other@example.com")
    project = source(client, owner)
    blueprint = save(client, owner, project)
    assert client.get(ROOT).status_code == 401
    assert client.get(ROOT, headers=other).json()["items"] == []
    assert (
        client.post(ROOT, headers=other, json={"name": "Roubo", "source_project_id": project["id"]}).status_code == 404
    )
    for verb, suffix, data in [
        ("GET", "", None),
        ("PUT", "", {"name": "Editado", "category": "geral"}),
        ("DELETE", "", None),
        ("POST", "/projects", {"name": "Novo indevido"}),
    ]:
        denied = client.request(verb, ROOT + f"/{blueprint['id']}" + suffix, headers=other, json=data)
        absent = client.request(verb, ROOT + f"/{uuid4()}" + suffix, headers=other, json=data)
        assert denied.status_code == absent.status_code == 404
        assert denied.json() == absent.json()
    for verb, path, data in [
        ("POST", ROOT, {"name": "Modelo", "source_project_id": project["id"]}),
        ("PUT", ROOT + f"/{blueprint['id']}", {"name": "Modelo", "category": "geral"}),
        ("POST", ROOT + f"/{blueprint['id']}/projects", {"name": "Novo projeto"}),
    ]:
        assert client.request(verb, path, headers=owner, json={**data, "user_id": str(uuid4())}).status_code == 422


@pytest.mark.parametrize("name", ["", "  ", "ab", "x" * 161])
def test_blueprint_name_limits_on_save_edit_use(client: TestClient, name: str) -> None:
    owner = auth(client)
    project = source(client, owner)
    blueprint = save(client, owner, project)
    assert client.post(ROOT, headers=owner, json={"name": name, "source_project_id": project["id"]}).status_code == 422
    assert (
        client.put(ROOT + f"/{blueprint['id']}", headers=owner, json={"name": name, "category": "geral"}).status_code
        == 422
    )
    assert client.post(ROOT + f"/{blueprint['id']}/projects", headers=owner, json={"name": name}).status_code == 422


def test_blueprint_description_and_snapshot_limits(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    owner = auth(client)
    project = source(client, owner)
    assert (
        client.post(
            ROOT, headers=owner, json={"name": "Modelo", "source_project_id": project["id"], "description": "x" * 1001}
        ).status_code
        == 422
    )
    monkeypatch.setattr(service, "MAX_STRUCTURE_BYTES", 1)
    assert (
        client.post(ROOT, headers=owner, json={"name": "Modelo", "source_project_id": project["id"]}).status_code == 413
    )
    assert client.get(ROOT, headers=owner).json()["total"] == 0


def test_blueprint_project_creation_rolls_back_partial_project_and_chain(
    client: TestClient,
    session_factory: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    owner = auth(client)
    project = source(client, owner)
    chain = client.post("/api/v1/chains", headers=owner, json={"name": "Fluxo", "project_id": project["id"]}).json()
    assert (
        client.post(
            f"/api/v1/chains/{chain['id']}/steps", headers=owner, json={"title": "Etapa", "base_input": "Base prompt"}
        ).status_code
        == 201
    )
    blueprint = save(client, owner, project)
    before = client.portal.call(snapshot, session_factory)

    def fail(**kwargs: object) -> None:
        raise RuntimeError("Injected step failure")

    monkeypatch.setattr(service, "PromptChainStep", fail)
    with pytest.raises(RuntimeError, match="Injected step failure"):
        client.post(ROOT + f"/{blueprint['id']}/projects", headers=owner, json={"name": "Falha transacional"})
    assert client.portal.call(snapshot, session_factory) == before


def test_blueprint_save_rolls_back_flushed_snapshot(
    client: TestClient,
    session_factory: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    owner = auth(client)
    project = source(client, owner)
    before = client.portal.call(snapshot, session_factory)

    async def fail_commit(session: AsyncSession) -> None:
        await session.flush()
        raise RuntimeError("Injected commit failure")

    with monkeypatch.context() as patch:
        patch.setattr(AsyncSession, "commit", fail_commit)
        with pytest.raises(RuntimeError, match="Injected commit failure"):
            client.post(ROOT, headers=owner, json={"name": "Falha transacional", "source_project_id": project["id"]})
    assert client.portal.call(snapshot, session_factory) == before


def test_blueprint_list_pagination_and_empty_structure(client: TestClient) -> None:
    owner = auth(client)
    project = source(client, owner)
    for _ in range(3):
        blueprint = save(client, owner, project)
        assert blueprint["structure"]["chains"] == [] and blueprint["category"] == "geral"
    first = client.get(ROOT + "?limit=2", headers=owner).json()
    second = client.get(ROOT + "?limit=2&offset=2", headers=owner).json()
    assert first["total"] == second["total"] == 3
    assert len(first["items"]) == 2 and len(second["items"]) == 1
    assert not {item["id"] for item in first["items"]} & {item["id"] for item in second["items"]}
