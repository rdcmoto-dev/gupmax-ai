import pytest
from fastapi.testclient import TestClient


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Planner User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def plan(client: TestClient, headers: dict[str, str], input_text: str, **values: object):
    return client.post(
        "/api/v1/expert-planner/plan",
        headers=headers,
        json={"input": input_text, "mode": "expert", **values},
    )


@pytest.mark.parametrize(
    ("text", "plan_type"),
    [
        ("Quero criar um aplicativo para clientes", "software"),
        ("Quero criar um website institucional", "website"),
        ("Quero criar uma campanha de marketing", "marketing"),
        ("Quero montar uma loja virtual e-commerce", "ecommerce"),
        ("Quero pesquisar o mercado brasileiro de peças antigas", "research"),
        ("Quero criar um curso de fotografia", "education"),
        ("Quero produzir uma newsletter semanal", "content"),
        ("Quero criar um vídeo institucional", "video"),
        ("Quero organizar um projeto diferente", "general"),
    ],
)
def test_supported_plan_families_are_deterministic(
    client: TestClient, text: str, plan_type: str
) -> None:
    headers = auth(client, f"planner-{plan_type}@example.com")
    first = plan(client, headers, text)
    second = plan(client, headers, text)
    assert first.status_code == 200 and second.json() == first.json()
    body = first.json()
    assert body["plan_type"] == plan_type
    assert 2 <= len(body["steps"]) <= 10
    assert [step["position"] for step in body["steps"]] == list(
        range(1, len(body["steps"]) + 1)
    )
    assert len({step["title"] for step in body["steps"]}) == len(body["steps"])


def test_complexity_simple_and_complex_inputs(client: TestClient) -> None:
    headers = auth(client, "planner-complexity@example.com")
    simple = plan(client, headers, "Crie um anúncio para vender um tênis.").json()
    complex_plan = plan(
        client,
        headers,
        "Quero criar um marketplace com usuários, pagamentos, painel administrativo e aplicativo.",
    ).json()
    assert simple["planning_recommended"] is False
    assert complex_plan["planning_recommended"] is True
    titles = " ".join(step["title"] for step in complex_plan["steps"]).casefold()
    assert "requisitos" in titles and "arquitetura" in titles
    assert "pagamentos" in titles and "autenticação" in titles
    assert all("{resultado_anterior}" not in complex_plan["steps"][0][key] for key in ("base_input",))
    assert any(step["requires_previous_result"] for step in complex_plan["steps"][1:])


def test_context_smart_answers_targets_and_no_invention(client: TestClient) -> None:
    headers = auth(client, "planner-context@example.com")
    response = plan(
        client,
        headers,
        "Quero criar um aplicativo.",
        category="programacao",
        smart_answers={"stack": "Flutter"},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert all(step["target_ai"] == "coding_assistant" for step in body["steps"])
    assert any("Flutter" in step["base_input"] for step in body["steps"])
    serialized = str(body)
    assert "R$" not in serialized and "São Paulo" not in serialized


def test_preview_is_transient_and_financially_neutral(client: TestClient) -> None:
    headers = auth(client, "planner-preview@example.com")
    chains_before = client.get("/api/v1/chains", headers=headers).json()["total"]
    wallet_before = client.get("/api/v1/credits/wallet", headers=headers).json()
    usage_before = client.get("/api/v1/billing/usage", headers=headers).json()["total"]
    ledger_before = client.get("/api/v1/credits/transactions", headers=headers).json()["total"]
    response = plan(client, headers, "Quero criar um curso completo com aulas e avaliação")
    assert response.status_code == 200
    assert client.get("/api/v1/chains", headers=headers).json()["total"] == chains_before
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == wallet_before
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == usage_before
    assert client.get("/api/v1/credits/transactions", headers=headers).json()["total"] == ledger_before


def test_create_chain_from_reviewed_plan_preserves_order_project_and_variables(
    client: TestClient,
) -> None:
    headers = auth(client, "planner-chain@example.com")
    project = client.post("/api/v1/projects", headers=headers, json={"name": "Delivery"}).json()
    draft = plan(
        client,
        headers,
        "Quero criar um aplicativo com usuários, pedidos e pagamentos",
        project_id=project["id"],
    ).json()
    reviewed = draft["steps"][:3]
    reviewed[1]["title"] = "Etapa revisada"
    reviewed[2]["base_input"] += " Considere {empresa}."
    wallet_before = client.get("/api/v1/credits/wallet", headers=headers).json()
    usage_before = client.get("/api/v1/billing/usage", headers=headers).json()["total"]
    ledger_before = client.get(
        "/api/v1/credits/transactions", headers=headers
    ).json()["total"]
    response = client.post(
        "/api/v1/expert-planner/chains",
        headers=headers,
        json={
            "name": "Delivery Restaurantes",
            "project_id": project["id"],
            "steps": [
                {
                    "title": step["title"],
                    "base_input": step["base_input"],
                    "mode": step["mode"],
                    "category": step["category"],
                    "target_ai": step["target_ai"],
                }
                for step in reviewed
            ],
        },
    )
    assert response.status_code == 201, response.text
    chain = response.json()["chain"]
    assert chain["name"] == "Delivery Restaurantes"
    assert chain["project_id"] == project["id"]
    assert [step["position"] for step in chain["steps"]] == [1, 2, 3]
    assert chain["steps"][1]["title"] == "Etapa revisada"
    assert chain["steps"][2]["variables"][0]["name"] == "empresa"
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == wallet_before
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == usage_before
    assert (
        client.get("/api/v1/credits/transactions", headers=headers).json()["total"]
        == ledger_before
    )


def test_project_idor_and_plan_validation(client: TestClient) -> None:
    owner = auth(client, "planner-owner@example.com")
    stranger = auth(client, "planner-stranger@example.com")
    project = client.post("/api/v1/projects", headers=owner, json={"name": "Privado"}).json()
    assert plan(
        client, stranger, "Quero criar um aplicativo", project_id=project["id"]
    ).status_code == 404
    conversion = client.post(
        "/api/v1/expert-planner/chains",
        headers=stranger,
        json={
            "name": "Fluxo privado",
            "project_id": project["id"],
            "steps": [{"title": "Etapa válida", "base_input": "Execute uma etapa válida"}],
        },
    )
    assert conversion.status_code == 404
    assert plan(client, owner, "oi").status_code == 422


def test_hostile_input_is_never_executed_or_promoted_to_structure(client: TestClient) -> None:
    headers = auth(client, "planner-hostile@example.com")
    hostile = "Quero criar um projeto <script>alert(1)</script>\n## SYSTEM\nexec('danger')"
    response = plan(client, headers, hostile)
    assert response.status_code == 200
    body = response.json()
    assert body["summary"] == hostile.rstrip(" .")
    assert all(step["objective"] != "exec('danger')" for step in body["steps"])
