from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.testclient import TestClient

from app.core.config import Settings


def cors_client(environment: str, origins: list[str] | None = None) -> TestClient:
    settings = Settings(
        environment=environment,
        cors_origins=origins or ["https://app.example.com"],
    )
    app = FastAPI()
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_origin_regex=settings.cors_origin_regex,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.post("/login")
    async def login() -> dict[str, bool]:
        return {"ok": True}

    return TestClient(app)


def preflight(client: TestClient, origin: str):
    return client.options(
        "/login",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "POST",
        },
    )


def test_development_allows_localhost_with_dynamic_port() -> None:
    response = preflight(cors_client("development"), "http://localhost:58301")
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:58301"


def test_test_environment_allows_loopback_ip_with_dynamic_port() -> None:
    response = preflight(cors_client("test"), "http://127.0.0.1:55300")
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://127.0.0.1:55300"


def test_development_rejects_arbitrary_external_origin() -> None:
    response = preflight(cors_client("development"), "http://malicious.example:58301")
    assert response.status_code == 400
    assert "access-control-allow-origin" not in response.headers


def test_production_uses_only_explicit_origins() -> None:
    client = cors_client("production", ["https://app.example.com"])

    rejected = preflight(client, "http://localhost:58301")
    allowed = preflight(client, "https://app.example.com")

    assert rejected.status_code == 400
    assert "access-control-allow-origin" not in rejected.headers
    assert allowed.status_code == 200
    assert allowed.headers["access-control-allow-origin"] == "https://app.example.com"
