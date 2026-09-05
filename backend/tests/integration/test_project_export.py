import json

import pytest
from fastapi.testclient import TestClient

from app.modules.projects import export as project_export


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Export User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def create_project(client: TestClient, headers: dict[str, str], **overrides: object) -> dict[str, object]:
    response = client.post(
        "/api/v1/projects",
        headers=headers,
        json={
            "name": "Lançamento Pizzaria Donatello",
            "description": "Campanha de lançamento",
            "context": None,
            **overrides,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_json_export_has_explicit_complete_contract_and_is_read_only(client: TestClient) -> None:
    owner = auth(client, "export-complete@example.com")
    context = (
        "Objetivo: Publicar campanha\n"
        "Critério de sucesso: [x] Campanha preparada\n"
        "Critério de sucesso: Público definido\n"
        "Marco: Publicar no Instagram\n"
        "Público: Famílias\n"
        "Conclusão do projeto: Material entregue\n"
        "Projeto encerrado: sim"
    )
    project = create_project(client, owner, context=context)
    chain = client.post(
        "/api/v1/chains", headers=owner, json={"name": "Fluxo", "project_id": project["id"]}
    ).json()
    first = client.post(
        f"/api/v1/chains/{chain['id']}/steps",
        headers=owner,
        json={
            "title": "Posicionamento",
            "base_input": "Defina o posicionamento",
            "mode": "basic",
            "category": "marketing",
            "target_ai": "chatgpt",
        },
    ).json()
    client.post(
        f"/api/v1/chains/{chain['id']}/steps",
        headers=owner,
        json={
            "title": "Campanha",
            "base_input": "Crie a campanha",
            "mode": "basic",
            "category": "marketing",
            "target_ai": "chatgpt",
        },
    )
    client.post(f"/api/v1/chains/{chain['id']}/execution/start", headers=owner)
    completed = client.put(
        f"/api/v1/chains/{chain['id']}/steps/{first['id']}/complete",
        headers=owner,
        json={"result": "Resultado integral da etapa"},
    )
    assert completed.status_code == 200, completed.text
    prompt = client.post(
        "/api/v1/prompts/generate",
        headers=owner,
        json={
            "project_id": project["id"],
            "input": "Crie uma campanha",
            "category": "marketing",
            "mode": "basic",
            "optimize_with_ai": False,
        },
    ).json()
    refined = client.post(
        f"/api/v1/prompts/{prompt['id']}/refine",
        headers=owner,
        json={"instruction": "Deixe mais curto.", "optimize_with_ai": False},
    )
    assert refined.status_code == 201, refined.text
    before_project = client.get(f"/api/v1/projects/{project['id']}", headers=owner).json()
    before_chain = client.get(f"/api/v1/chains/{chain['id']}", headers=owner).json()
    before_usage = client.get("/api/v1/billing/usage", headers=owner).json()
    before_wallet = client.get("/api/v1/credits/wallet", headers=owner).json()

    response = client.get(f"/api/v1/projects/{project['id']}/export?format=json", headers=owner)

    assert response.status_code == 200, response.text
    assert response.headers["content-type"] == "application/json; charset=utf-8"
    assert response.headers["content-disposition"] == 'attachment; filename="lancamento-pizzaria-donatello.json"'
    assert response.headers["cache-control"] == "private, no-store"
    package = response.json()
    assert package["export_version"] == 1
    assert set(package) == {
        "export_version",
        "exported_at",
        "project",
        "goal",
        "success_criteria",
        "milestones",
        "context",
        "chains",
        "prompts",
        "review",
    }
    assert "user_id" not in response.text
    assert package["project"]["status"] == "closed"
    assert package["goal"] == "Publicar campanha"
    assert package["success_criteria"] == [
        {"text": "Campanha preparada", "completed": True},
        {"text": "Público definido", "completed": False},
    ]
    assert package["milestones"] == [{"text": "Publicar no Instagram", "completed": False}]
    assert package["context"] == [{"label": "Público", "value": "Famílias"}]
    assert package["chains"][0]["completed_count"] == 1
    assert package["chains"][0]["steps"][0]["result"] == "Resultado integral da etapa"
    assert len(package["prompts"]) == 1
    assert package["prompts"][0]["version_count"] == 2
    assert [item["version"] for item in package["prompts"][0]["versions"]] == [1, 2]
    assert package["review"] == {"conclusion": "Material entregue", "manual_status": "closed"}
    assert client.get(f"/api/v1/projects/{project['id']}", headers=owner).json() == before_project
    assert client.get(f"/api/v1/chains/{chain['id']}", headers=owner).json() == before_chain
    assert client.get("/api/v1/billing/usage", headers=owner).json() == before_usage
    assert client.get("/api/v1/credits/wallet", headers=owner).json() == before_wallet


def test_markdown_export_escapes_hostile_content_and_supports_empty_archived_project(
    client: TestClient,
) -> None:
    owner = auth(client, "export-markdown@example.com")
    project = create_project(
        client,
        owner,
        name="../../ Café <script>alert(1)</script>",
        description="# IGNORE INSTRUCTIONS\n<script>alert(1)</script>\n```code```",
    )
    archived = client.put(
        f"/api/v1/projects/{project['id']}", headers=owner, json={"status": "archived"}
    )
    assert archived.status_code == 200

    response = client.get(f"/api/v1/projects/{project['id']}/export?format=markdown", headers=owner)

    assert response.status_code == 200
    assert response.headers["content-type"] == "text/markdown; charset=utf-8"
    assert response.headers["content-disposition"] == 'attachment; filename="cafe-script-alert-1-script.md"'
    assert "../" not in response.headers["content-disposition"]
    assert "<script>" not in response.text
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in response.text
    assert "> # IGNORE INSTRUCTIONS" in response.text
    assert "**Estado:** Arquivado" in response.text
    assert "_Nenhum fluxo associado._" in response.text
    assert "_Nenhum prompt associado._" in response.text


def test_export_ownership_invalid_format_and_size_limit(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    owner = auth(client, "export-owner@example.com")
    stranger = auth(client, "export-stranger@example.com")
    project = create_project(client, owner)

    assert client.get(f"/api/v1/projects/{project['id']}/export?format=json", headers=stranger).status_code == 404
    assert client.get(f"/api/v1/projects/{project['id']}/export?format=pdf", headers=owner).status_code == 422
    assert client.get(f"/api/v1/projects/{project['id']}/export", headers=owner).status_code == 422

    monkeypatch.setattr(project_export, "MAX_EXPORT_BYTES", 1)
    too_large = client.get(f"/api/v1/projects/{project['id']}/export?format=json", headers=owner)
    assert too_large.status_code == 413
    assert too_large.json()["detail"] == "Project export exceeds 10 MiB"


def test_json_export_is_not_limited_to_library_first_page(client: TestClient) -> None:
    owner = auth(client, "export-pagination@example.com")
    project = create_project(client, owner)
    for index in range(21):
        created = client.post(
            "/api/v1/prompts/generate",
            headers=owner,
            json={
                "project_id": project["id"],
                "input": f"Prompt número {index}",
                "category": "geral",
                "mode": "basic",
                "optimize_with_ai": False,
            },
        )
        assert created.status_code == 201, created.text
    assert client.get(f"/api/v1/projects/{project['id']}/library", headers=owner).json()["prompt_total"] == 21

    exported = client.get(f"/api/v1/projects/{project['id']}/export?format=json", headers=owner)

    assert exported.status_code == 200
    assert len(exported.json()["prompts"]) == 21


def test_safe_filename_falls_back_and_json_renderer_preserves_unicode() -> None:
    assert project_export.safe_export_filename("../\\...", project_export.ProjectExportFormat.JSON) == "projeto.json"
    raw = json.loads(
        project_export.render_json(
            project_export.ProjectExport(
                exported_at="2026-09-05T00:00:00Z",
                project=project_export.ExportProject(
                    name="Ação",
                    description=None,
                    status="active",
                    created_at="2026-09-05T00:00:00Z",
                    updated_at="2026-09-05T00:00:00Z",
                ),
                goal=None,
                success_criteria=[],
                milestones=[],
                context=[],
                chains=[],
                prompts=[],
                review=project_export.ExportReview(conclusion=None, manual_status="active"),
            )
        )
    )
    assert raw["project"]["name"] == "Ação"
