import pytest
from fastapi.testclient import TestClient


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Intent User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


@pytest.mark.parametrize(
    ("text", "category"),
    [
        ("Crie uma campanha para minha empresa", "marketing"),
        ("Quero vender um tênis no Instagram", "vendas"),
        ("Crie uma API em Python com FastAPI", "programacao"),
        ("Crie uma imagem realista de um produto", "imagem"),
        ("Faça um vídeo de 15 segundos para Instagram", "video"),
        ("Escreva um contrato comercial", "negocios"),
        ("Explique fotossíntese para uma criança", "educacao"),
        ("Escreva um artigo sobre sustentabilidade", "escrita"),
        ("Crie uma página de produto para minha loja virtual", "ecommerce"),
        ("Crie um carrossel para o LinkedIn", "redes_sociais"),
        ("Organize minhas tarefas em um cronograma", "produtividade"),
        ("Preciso de ajuda com uma ideia diferente", "geral"),
    ],
)
def test_detects_supported_intent_families(
    client: TestClient, text: str, category: str
) -> None:
    headers = auth(client, f"intent-{category}@example.com")
    response = client.post("/api/v1/intent/analyze", headers=headers, json={"input": text})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["suggested_category"] == category
    assert 0 <= body["confidence"] <= 1
    assert len(body["suggested_questions"]) <= 5
    assert body["missing_information"] == [item["key"] for item in body["suggested_questions"]]


def test_entities_questions_determinism_and_financial_invariants(client: TestClient) -> None:
    headers = auth(client, "intent-entities@example.com")
    wallet = client.get("/api/v1/credits/wallet", headers=headers).json()
    usage = client.get("/api/v1/billing/usage", headers=headers).json()["total"]
    ledger = client.get("/api/v1/credits/transactions", headers=headers).json()["total"]
    payload = {"input": "Crie um VÍDEO de 15 segundos para Instagram divulgando um tênis."}
    first = client.post("/api/v1/intent/analyze", headers=headers, json=payload)
    second = client.post("/api/v1/intent/analyze", headers=headers, json=payload)
    assert first.status_code == 200 and second.json() == first.json()
    body = first.json()
    assert body["detected_entities"]["duration"] == "15 segundos"
    assert body["detected_entities"]["platform"] == "Instagram"
    assert "duration" not in body["missing_information"]
    assert "platform" not in body["missing_information"]
    assert len({item["key"] for item in body["suggested_questions"]}) == len(
        body["suggested_questions"]
    )
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == wallet
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == usage
    assert client.get("/api/v1/credits/transactions", headers=headers).json()["total"] == ledger


def test_sales_questions_expose_stable_smart_answer_keys(client: TestClient) -> None:
    headers = auth(client, "intent-smart-keys@example.com")
    response = client.post(
        "/api/v1/intent/analyze",
        headers=headers,
        json={"input": "Quero criar um anúncio para vender tênis feminino no Instagram."},
    )
    assert response.status_code == 200, response.text
    keys = {item["key"] for item in response.json()["suggested_questions"]}
    assert {"product_details", "audience", "tone"} <= keys
    assert "offer_details" not in keys


def test_programming_entities_and_safe_text_inputs(client: TestClient) -> None:
    headers = auth(client, "intent-code@example.com")
    response = client.post(
        "/api/v1/intent/analyze",
        headers=headers,
        json={"input": "Crie uma API em PYTHON com FastAPI para cadastrar produtos."},
    )
    assert response.status_code == 200
    assert response.json()["detected_entities"] | {
        "programming_language": "Python",
        "framework": "FastAPI",
    } == response.json()["detected_entities"]
    for text in (
        '{"action":"create","value":"<script>alert(1)</script>"}',
        "def run():\n    return {produto}",
        "const value = () => document.body;",
        ".card { color: red; }",
        "void main() => print('{resultado_anterior}');",
    ):
        analyzed = client.post("/api/v1/intent/analyze", headers=headers, json={"input": text})
        assert analyzed.status_code == 200
        assert analyzed.json()["summary"] == " ".join(text.split()).rstrip(" .")


def test_validation_accents_case_sizes_and_missing_entities(client: TestClient) -> None:
    headers = auth(client, "intent-validation@example.com")
    assert client.post("/api/v1/intent/analyze", headers=headers, json={"input": ""}).status_code == 422
    assert client.post("/api/v1/intent/analyze", headers=headers, json={"input": "oi"}).status_code == 422
    large = "Crie um texto " + "útil " * 1900
    assert len(large) < 10_000
    assert client.post("/api/v1/intent/analyze", headers=headers, json={"input": large}).status_code == 200
    general = client.post(
        "/api/v1/intent/analyze", headers=headers, json={"input": "PEDIDO ABSTRATO SEM ENTIDADES"}
    ).json()
    assert general["suggested_category"] == "geral"
    assert general["detected_entities"] == {}


def test_optional_project_and_template_ownership_returns_uniform_404(client: TestClient) -> None:
    owner = auth(client, "intent-owner@example.com")
    stranger = auth(client, "intent-stranger@example.com")
    project = client.post("/api/v1/projects", headers=owner, json={"name": "Privado"}).json()
    template = client.post(
        "/api/v1/templates",
        headers=owner,
        json={"name": "Privado", "template_content": "Crie {produto}", "base_input": "Crie {produto}"},
    ).json()
    for values in ({"project_id": project["id"]}, {"template_id": template["id"]}):
        response = client.post(
            "/api/v1/intent/analyze",
            headers=stranger,
            json={"input": "Crie uma campanha", **values},
        )
        assert response.status_code == 404
