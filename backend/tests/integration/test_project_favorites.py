from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.db.base import Base
from app.modules.ai_gateway.service import AIGatewayService


def register(client: TestClient, email: str = "favorites@example.com") -> dict:
    response = client.post("/api/v1/auth/register", json={
        "email": email, "full_name": "Favorites User", "password": "SecurePassword123!",
    })
    assert response.status_code == 201, response.text
    return response.json()


def headers(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


def create(client: TestClient, owner: dict[str, str]) -> dict:
    response = client.post("/api/v1/projects", headers=owner, json={
        "name": "Projeto favorito", "description": "Descrição preservada",
        "context": "Objetivo: Entregar\nCritério de sucesso: [x] Pronto\nMarco: [x] Publicado\n"
        "Público: <script>texto</script>\nConclusão do projeto: Entregue\nProjeto encerrado: sim",
    })
    assert response.status_code == 201, response.text
    assert response.json()["is_favorite"] is False
    return response.json()


def test_favorite_persists_across_requests_logout_login_and_is_idempotent(client: TestClient) -> None:
    tokens = register(client)
    owner = headers(tokens)
    project = create(client, owner)
    path = f"/api/v1/projects/{project['id']}"
    for _ in range(2):
        response = client.put(path + "/favorite", headers=owner, json={"is_favorite": True})
        assert response.status_code == 200, response.text
        assert response.json() == {**project, "is_favorite": True}
    assert client.post("/api/v1/auth/logout", json={"refresh_token": tokens["refresh_token"]}).status_code == 204
    login = client.post("/api/v1/auth/login", json={"email": "favorites@example.com", "password": "SecurePassword123!"})
    assert login.status_code == 200
    owner = headers(login.json())
    assert client.get(path, headers=owner).json()["is_favorite"] is True
    assert client.get("/api/v1/projects", headers=owner).json()["items"][0]["is_favorite"] is True
    for _ in range(2):
        response = client.put(path + "/favorite", headers=owner, json={"is_favorite": False})
        assert response.status_code == 200
        assert response.json() == project
    assert client.get(path, headers=owner).json()["is_favorite"] is False


def test_favorite_enforces_authentication_and_uniform_ownership(client: TestClient) -> None:
    owner = headers(register(client))
    stranger = headers(register(client, "stranger@example.com"))
    project = create(client, owner)
    path = f"/api/v1/projects/{project['id']}/favorite"
    assert client.put(path, json={"is_favorite": True}).status_code == 401
    for value in (True, False):
        denied = client.put(path, headers=stranger, json={"is_favorite": value})
        missing = client.put(f"/api/v1/projects/{uuid4()}/favorite", headers=stranger, json={"is_favorite": value})
        assert denied.status_code == missing.status_code == 404
        assert denied.json() == missing.json()
    assert client.get(f"/api/v1/projects/{project['id']}", headers=stranger).status_code == 404
    assert client.get("/api/v1/projects", headers=stranger).json()["items"] == []
    assert client.get(f"/api/v1/projects/{project['id']}", headers=owner).json()["is_favorite"] is False


@pytest.mark.parametrize("payload", [
    {}, {"is_favorite": None}, {"is_favorite": "true"}, {"is_favorite": 1},
    {"is_favorite": True, "user_id": str(uuid4())},
    {"is_favorite": True, "context": "alterado"},
    {"is_favorite": True, "status": "archived"},
])
def test_favorite_rejects_invalid_or_extra_fields(client: TestClient, payload: dict) -> None:
    owner = headers(register(client))
    project = create(client, owner)
    path = f"/api/v1/projects/{project['id']}"
    assert client.put(path + "/favorite", headers=owner, json=payload).status_code == 422
    assert client.get(path, headers=owner).json()["is_favorite"] is False


def test_favorite_changes_only_preference_in_entire_database(
    client: TestClient, session_factory: async_sessionmaker[AsyncSession], monkeypatch: pytest.MonkeyPatch,
) -> None:
    owner = headers(register(client))
    project = create(client, owner)
    path = f"/api/v1/projects/{project['id']}"
    chain = client.post("/api/v1/chains", headers=owner, json={"name": "Fluxo favorito", "project_id": project["id"]})
    assert chain.status_code == 201
    chain_path = f"/api/v1/chains/{chain.json()['id']}"
    first = client.post(chain_path + "/steps", headers=owner, json={
        "title": "Primeira etapa", "base_input": "Base original", "mode": "basic", "category": "marketing",
    })
    assert first.status_code == 201
    assert client.post(chain_path + "/steps", headers=owner, json={
        "title": "Segunda etapa", "base_input": "Use {resultado_anterior}", "mode": "basic", "category": "marketing",
    }).status_code == 201
    assert client.post(chain_path + "/execution/start", headers=owner).status_code == 200
    assert client.put(chain_path + f"/steps/{first.json()['id']}/complete", headers=owner,
                      json={"result": "Resultado preservado"}).status_code == 200
    prompt = client.post("/api/v1/prompts/generate", headers=owner, json={
        "project_id": project["id"], "input": "Campanha histórica", "mode": "basic",
        "category": "marketing", "optimize_with_ai": False,
    })
    assert prompt.status_code == 201
    assert client.post(f"/api/v1/prompts/{prompt.json()['id']}/refine", headers=owner,
                       json={"instruction": "Mais curto", "optimize_with_ai": False}).status_code == 201
    template = client.post("/api/v1/templates", headers=owner, json={
        "name": "Template preservado", "template_content": "Conteúdo original", "base_input": "Base original",
    })
    assert template.status_code == 201, template.text
    assert client.put(path + f"/templates/{template.json()['id']}", headers=owner).status_code == 204
    assert client.put(path, headers=owner, json={"status": "archived"}).status_code == 200

    async def snapshot() -> dict:
        async with session_factory() as session:
            result = {}
            for table in Base.metadata.sorted_tables:
                rows = (await session.execute(select(table).order_by(*table.primary_key.columns))).mappings().all()
                result[table.name] = [dict(row) for row in rows]
            return result

    async def forbidden_ai(*args: object, **kwargs: object) -> None:
        pytest.fail("Favorite must not invoke AI")

    monkeypatch.setattr(AIGatewayService, "generate", forbidden_ai)
    monkeypatch.setattr(AIGatewayService, "stream", forbidden_ai)
    before = client.portal.call(snapshot)
    for value in (True, False):
        response = client.put(path + "/favorite", headers=owner, json={"is_favorite": value})
        assert response.status_code == 200
        after = client.portal.call(snapshot)
        expected = {**before, "projects": [{**row, "is_favorite": value} for row in before["projects"]]}
        assert after == expected
    assert client.put(path + "/favorite", headers=owner, json={"is_favorite": True}).status_code == 200
    duplicate = client.post(path + "/duplicate", headers=owner, json={"name": "Cópia independente"})
    assert duplicate.status_code == 201
    assert duplicate.json()["is_favorite"] is False
    assert client.get(path, headers=owner).json()["is_favorite"] is True
