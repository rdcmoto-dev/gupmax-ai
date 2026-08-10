from fastapi.testclient import TestClient


def _register(
    client: TestClient, email: str = "ana@example.com", password: str = "SecurePassword123!"
) -> dict[str, object]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Ana Silva", "password": password},
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_registration_login_and_protected_identity(client: TestClient) -> None:
    registration = _register(client)
    access_token = registration["access_token"]

    me = client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {access_token}"})
    assert me.status_code == 200
    assert me.json()["email"] == "ana@example.com"
    assert me.json()["role"] == "user"

    login = client.post("/api/v1/auth/login", json={"email": "ana@example.com", "password": "SecurePassword123!"})
    assert login.status_code == 200
    assert login.json()["token_type"] == "bearer"


def test_refresh_rotation_and_logout(client: TestClient) -> None:
    registration = _register(client)
    first_refresh = registration["refresh_token"]

    refresh = client.post("/api/v1/auth/refresh", json={"refresh_token": first_refresh})
    assert refresh.status_code == 200
    second_refresh = refresh.json()["refresh_token"]

    reused = client.post("/api/v1/auth/refresh", json={"refresh_token": first_refresh})
    assert reused.status_code == 401

    logout = client.post("/api/v1/auth/logout", json={"refresh_token": second_refresh})
    assert logout.status_code == 204
    revoked = client.post("/api/v1/auth/refresh", json={"refresh_token": second_refresh})
    assert revoked.status_code == 401


def test_password_change_revokes_existing_refresh_tokens(client: TestClient) -> None:
    registration = _register(client)
    access_token = registration["access_token"]
    refresh_token = registration["refresh_token"]

    change = client.patch(
        "/api/v1/users/me/password",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"current_password": "SecurePassword123!", "new_password": "NewSecurePassword123!"},
    )
    assert change.status_code == 204
    assert client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token}).status_code == 401
    assert (
        client.post(
            "/api/v1/auth/login", json={"email": "ana@example.com", "password": "NewSecurePassword123!"}
        ).status_code
        == 200
    )
