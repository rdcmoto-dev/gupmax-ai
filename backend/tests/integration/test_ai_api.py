from fastapi.testclient import TestClient


def test_ai_generation_requires_authentication(client: TestClient) -> None:
    response = client.post("/api/v1/ai/generate", json={"user_prompt": "Olá"})

    assert response.status_code == 401


def test_openapi_documents_ai_endpoints(client: TestClient) -> None:
    response = client.get("/api/v1/openapi.json")

    assert response.status_code == 200
    assert "/api/v1/ai/generate" in response.json()["paths"]
