from fastapi.testclient import TestClient


def _auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Prompt User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _generate(client: TestClient, headers: dict[str, str], text: str = "Crie um anúncio de tênis"):
    return client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "input": text,
            "category": "marketing",
            "language": "pt-BR",
            "tone": "persuasivo",
            "mode": "pro",
            "optimize_with_ai": False,
        },
    )


def test_prompt_endpoints_require_authentication(client: TestClient) -> None:
    assert client.post("/api/v1/prompts/generate", json={"input": "Crie algo útil"}).status_code == 401
    assert client.get("/api/v1/prompts").status_code == 401


def test_generate_list_get_update_delete_without_ai(client: TestClient) -> None:
    headers = _auth(client, "prompt@example.com")
    generated = _generate(client, headers)
    assert generated.status_code == 201, generated.text
    body = generated.json()
    assert body["provider"] is None
    assert body["usage"] is None
    assert body["status"] == "generated"
    assert "## OBJECTIVE" in body["generated_prompt"]

    listing = client.get("/api/v1/prompts?category=marketing&mode=pro&order=desc", headers=headers)
    assert listing.status_code == 200
    assert listing.json()["total"] == 1
    assert listing.json()["offset"] == 0

    prompt_id = body["id"]
    fetched = client.get(f"/api/v1/prompts/{prompt_id}", headers=headers)
    assert fetched.status_code == 200
    updated = client.put(f"/api/v1/prompts/{prompt_id}", headers=headers, json={"title": "Campanha primavera"})
    assert updated.status_code == 200
    assert updated.json()["title"] == "Campanha primavera"
    deleted = client.delete(f"/api/v1/prompts/{prompt_id}", headers=headers)
    assert deleted.status_code == 204
    assert client.get(f"/api/v1/prompts/{prompt_id}", headers=headers).status_code == 404


def test_prompt_ownership_prevents_idor(client: TestClient) -> None:
    owner = _auth(client, "owner@example.com")
    stranger = _auth(client, "stranger@example.com")
    prompt_id = _generate(client, owner, "Conteúdo privado").json()["id"]

    assert client.get(f"/api/v1/prompts/{prompt_id}", headers=stranger).status_code == 404
    assert client.put(f"/api/v1/prompts/{prompt_id}", headers=stranger, json={"title": "Invasão"}).status_code == 404
    assert client.delete(f"/api/v1/prompts/{prompt_id}", headers=stranger).status_code == 404
    assert client.get("/api/v1/prompts", headers=stranger).json()["total"] == 0


def test_prompt_validation_and_pagination(client: TestClient) -> None:
    headers = _auth(client, "validation@example.com")
    assert _generate(client, headers, "x").status_code == 422
    assert client.get("/api/v1/prompts?limit=101", headers=headers).status_code == 422
