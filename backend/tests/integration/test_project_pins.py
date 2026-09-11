from uuid import uuid4

from fastapi.testclient import TestClient


def register(client: TestClient, email: str) -> dict:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Pinned User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def create(client: TestClient, headers: dict, number: int) -> dict:
    response = client.post("/api/v1/projects", headers=headers, json={"name": f"Projeto fixado {number}"})
    assert response.status_code == 201, response.text
    return response.json()


def test_pin_is_owned_persistent_and_changes_only_pin(client: TestClient) -> None:
    owner = register(client, "pins-owner@example.com")
    stranger = register(client, "pins-stranger@example.com")
    project = create(client, owner, 1)
    path = f"/api/v1/projects/{project['id']}/pin"
    pinned = client.put(path, headers=owner, json={"is_pinned": True})
    assert pinned.status_code == 200
    assert pinned.json() == {**project, "is_pinned": True}
    assert client.get(f"/api/v1/projects/{project['id']}", headers=owner).json()["is_pinned"] is True
    for target in (path, f"/api/v1/projects/{uuid4()}/pin"):
        assert client.put(target, headers=stranger, json={"is_pinned": False}).status_code == 404
    assert client.put(path, headers=owner, json={"is_pinned": False}).json() == project


def test_pin_limit_and_archive_contract(client: TestClient) -> None:
    owner = register(client, "pins-limit@example.com")
    projects = [create(client, owner, index) for index in range(4)]
    for project in projects[:3]:
        assert client.put(
            f"/api/v1/projects/{project['id']}/pin", headers=owner, json={"is_pinned": True}
        ).status_code == 200
    limited = client.put(
        f"/api/v1/projects/{projects[3]['id']}/pin", headers=owner, json={"is_pinned": True}
    )
    assert limited.status_code == 409
    assert limited.json()["detail"] == {
        "code": "project_pin_limit_reached",
        "message": "Você pode fixar até 3 projetos. Desafixe um projeto para continuar.",
    }
    assert "Ã" not in limited.content.decode("utf-8")
    archived = client.put(
        f"/api/v1/projects/{projects[0]['id']}", headers=owner, json={"status": "archived"}
    )
    assert archived.status_code == 200 and archived.json()["is_pinned"] is False
    assert client.put(
        f"/api/v1/projects/{projects[3]['id']}/pin", headers=owner, json={"is_pinned": True}
    ).status_code == 200


def test_pin_payload_is_strict_and_new_projects_start_unpinned(client: TestClient) -> None:
    owner = register(client, "pins-input@example.com")
    project = create(client, owner, 1)
    path = f"/api/v1/projects/{project['id']}/pin"
    for payload in ({}, {"is_pinned": "true"}, {"is_pinned": True, "user_id": str(uuid4())}):
        assert client.put(path, headers=owner, json=payload).status_code == 422
    assert project["is_pinned"] is False
