from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.modules.prompt_engine.builder import PromptBuilder
from app.modules.prompt_engine.enums import PromptCategory
from app.modules.prompt_engine.schemas import PromptGenerateRequest


def _auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Interview User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _start(
    client: TestClient,
    headers: dict[str, str],
    *,
    mode: str = "pro",
    category: str = "marketing",
    initial_request: str = "Quero criar um anúncio para vender um tênis feminino",
) -> dict[str, Any]:
    response = client.post(
        "/api/v1/interviews",
        headers=headers,
        json={
            "initial_request": initial_request,
            "mode": mode,
            "category": category,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _value(question: dict[str, Any]) -> str | bool | list[str]:
    match question["type"]:
        case "single_choice":
            return question["options"][0]
        case "multi_choice":
            return [question["options"][0]]
        case "boolean":
            return True
        case _:
            return f"Resposta para {question['key']}"


def test_interview_endpoints_require_authentication(client: TestClient) -> None:
    assert client.post("/api/v1/interviews", json={"initial_request": "Uma ideia", "mode": "pro"}).status_code == 401
    assert client.get("/api/v1/interviews/00000000-0000-0000-0000-000000000001").status_code == 401


@pytest.mark.parametrize("category", [category.value for category in PromptCategory])
def test_all_categories_produce_relevant_pro_questions(client: TestClient, category: str) -> None:
    headers = _auth(client, f"{category}@example.com")
    interview = _start(client, headers, category=category)
    assert interview["category"] == category
    assert interview["status"] == "active"
    assert len(interview["questions"]) == 4
    assert len({question["key"] for question in interview["questions"]}) == 4


def test_modes_have_formal_depth_and_basic_completes_without_questions(client: TestClient) -> None:
    headers = _auth(client, "modes@example.com")
    basic = _start(client, headers, mode="basic")
    pro = _start(client, headers, mode="pro")
    expert = _start(client, headers, mode="expert")

    assert basic["status"] == "ready" and basic["questions"] == []
    assert len(pro["questions"]) == 4
    assert len(expert["questions"]) > len(pro["questions"])

    completed = client.post(f"/api/v1/interviews/{basic['id']}/complete", headers=headers)
    assert completed.status_code == 200
    assert completed.json()["prompt_input"]["mode"] == "basic"


def test_adaptive_interview_omits_known_facts_and_persists_dynamic_snapshot(client: TestClient) -> None:
    headers = _auth(client, "adaptive@example.com")
    interview = _start(
        client,
        headers,
        initial_request=("Quero criar um anúncio para Instagram para mulheres de 18 a 35 anos com tom persuasivo."),
    )
    assert [question["key"] for question in interview["questions"]] == ["cta"]
    assert interview["progress"] == {
        "answered": 0,
        "total": 1,
        "required_answered": 0,
        "required_total": 1,
    }
    assert "facts" not in interview

    refreshed = client.get(f"/api/v1/interviews/{interview['id']}", headers=headers)
    assert refreshed.status_code == 200
    assert refreshed.json()["questions"] == interview["questions"]
    assert refreshed.json()["progress"] == interview["progress"]

    ready = client.post(
        f"/api/v1/interviews/{interview['id']}/answers",
        headers=headers,
        json={"answers": [{"question_key": "cta", "value": "Comprar agora"}]},
    )
    assert ready.status_code == 200
    assert ready.json()["status"] == "ready"
    completed = client.post(f"/api/v1/interviews/{interview['id']}/complete", headers=headers)
    assert completed.status_code == 200
    prompt_input = completed.json()["prompt_input"]
    assert prompt_input["tone"] == "persuasivo"
    assert prompt_input["audience"] == "mulheres de 18 a 35 anos"
    assert "Instagram" in prompt_input["context"]


def test_pro_can_start_ready_when_all_required_facts_are_explicit(client: TestClient) -> None:
    headers = _auth(client, "adaptive-ready@example.com")
    interview = _start(
        client,
        headers,
        initial_request=("Anúncio para Instagram para mulheres de 18 a 35 anos com tom persuasivo, CTA: compre agora."),
    )
    assert interview["status"] == "ready"
    assert interview["questions"] == []
    assert interview["progress"]["total"] == 0


def test_explicit_answer_overrides_extracted_fact(client: TestClient) -> None:
    headers = _auth(client, "adaptive-precedence@example.com")
    interview = _start(
        client,
        headers,
        initial_request=("Anúncio para Instagram para mulheres adultas com tom profissional, CTA: conheça agora."),
    )
    assert interview["status"] == "ready"
    override = client.post(
        f"/api/v1/interviews/{interview['id']}/answers",
        headers=headers,
        json={"answers": [{"question_key": "tone", "value": "persuasivo"}]},
    )
    assert override.status_code == 200
    assert override.json()["progress"]["total"] == 0
    completed = client.post(f"/api/v1/interviews/{interview['id']}/complete", headers=headers)
    assert completed.status_code == 200
    assert completed.json()["prompt_input"]["tone"] == "persuasivo"


def test_known_form_fields_omit_questions_and_feed_complete(client: TestClient) -> None:
    headers = _auth(client, "adaptive-form@example.com")
    response = client.post(
        "/api/v1/interviews",
        headers=headers,
        json={
            "initial_request": "Crie um anúncio para Instagram",
            "mode": "pro",
            "category": "marketing",
            "known_fields": {
                "input": "Crie um anúncio para Instagram",
                "mode": "pro",
                "category": "marketing",
                "language": "pt-BR",
                "tone": "elegante",
                "audience": "Mulheres de 18 a 35 anos",
                "context": "Lançamento de verão",
                "instructions": ["Destaque conforto"],
                "constraints": ["Não prometer frete grátis"],
                "optimize_with_ai": True,
                "comparison_target_ais": ["chatgpt", "claude"],
            },
        },
    )
    assert response.status_code == 201, response.text
    interview = response.json()
    assert [question["key"] for question in interview["questions"]] == ["cta"]
    ready = client.post(
        f"/api/v1/interviews/{interview['id']}/answers",
        headers=headers,
        json={"answers": [{"question_key": "cta", "value": "Comprar agora"}]},
    )
    assert ready.status_code == 200 and ready.json()["status"] == "ready"
    completed = client.post(f"/api/v1/interviews/{interview['id']}/complete", headers=headers)
    prompt = completed.json()["prompt_input"]
    assert prompt["tone"] == "elegante"
    assert prompt["audience"] == "Mulheres de 18 a 35 anos"
    assert prompt["instructions"] == ["Destaque conforto"]
    assert prompt["constraints"] == ["Não prometer frete grátis"]
    assert "Lançamento de verão" in prompt["context"]
    assert prompt["optimize_with_ai"] is True
    assert prompt["comparison_target_ais"] == ["chatgpt", "claude"]


def test_programming_requirements_answer_is_preserved_once_in_final_context(client: TestClient) -> None:
    headers = _auth(client, "adaptive-programming-regression@example.com")
    interview = _start(
        client,
        headers,
        mode="expert",
        category="programacao",
        initial_request="Crie um site em React para uma pizzaria com cardápio e botão de WhatsApp.",
    )
    keys = {question["key"] for question in interview["questions"]}
    assert "stack" not in keys
    assert "platform" not in keys
    assert "requirements" in keys

    expected_answer = "Cardápio online, botão de WhatsApp e layout responsivo."
    question_text = "Quais funcionalidades e requisitos precisam ser atendidos?"
    rejected_echo = client.post(
        f"/api/v1/interviews/{interview['id']}/answers",
        headers=headers,
        json={"answers": [{"question_key": "requirements", "value": question_text}]},
    )
    assert rejected_echo.status_code == 422

    answers = [
        {
            "question_key": question["key"],
            "value": expected_answer if question["key"] == "requirements" else _value(question),
        }
        for question in interview["questions"]
        if question["required"]
    ]
    answered = client.post(
        f"/api/v1/interviews/{interview['id']}/answers",
        headers=headers,
        json={"answers": answers},
    )
    assert answered.status_code == 200, answered.text
    persisted = {item["question_key"]: item["value"] for item in answered.json()["answers"]}
    assert persisted["requirements"] == expected_answer

    completed = client.post(f"/api/v1/interviews/{interview['id']}/complete", headers=headers)
    assert completed.status_code == 200, completed.text
    prompt_input = PromptGenerateRequest.model_validate(completed.json()["prompt_input"])
    assert prompt_input.context is not None
    assert prompt_input.context.count(question_text) == 1
    assert prompt_input.context.count(expected_answer) == 1
    assert "Plataforma: site" in prompt_input.context
    assert "Stack: React" in prompt_input.context

    final_prompt = PromptBuilder().build(prompt_input)
    context = final_prompt.split("## CONTEXT\n", 1)[1].split("\n\n## ", 1)[0]
    assert context.count(question_text) == 1
    assert context.count(expected_answer) == 1
    assert "Plataforma: site" in context
    assert "Stack: React" in context


def test_structured_answers_validation_progress_ready_and_idempotency(client: TestClient) -> None:
    headers = _auth(client, "answers@example.com")
    interview = _start(client, headers, mode="expert", category="redes_sociais")
    interview_id = interview["id"]
    types = {question["type"] for question in interview["questions"]}
    assert {"text", "multiline", "single_choice", "multi_choice", "boolean"} <= types

    choice = next(question for question in interview["questions"] if question["type"] == "single_choice")
    invalid = client.post(
        f"/api/v1/interviews/{interview_id}/answers",
        headers=headers,
        json={"answers": [{"question_key": choice["key"], "value": "opção inexistente"}]},
    )
    assert invalid.status_code == 422

    optional = next(question for question in interview["questions"] if not question["required"])
    optional_response = client.post(
        f"/api/v1/interviews/{interview_id}/answers",
        headers=headers,
        json={"answers": [{"question_key": optional["key"], "value": _value(optional)}]},
    )
    assert optional_response.status_code == 200
    assert optional_response.json()["status"] == "active"

    answers = [
        {"question_key": question["key"], "value": _value(question)}
        for question in interview["questions"]
        if question["required"]
    ]
    ready = client.post(f"/api/v1/interviews/{interview_id}/answers", headers=headers, json={"answers": answers})
    assert ready.status_code == 200, ready.text
    assert ready.json()["status"] == "ready"
    assert ready.json()["progress"]["required_answered"] == ready.json()["progress"]["required_total"]

    repeated = client.post(
        f"/api/v1/interviews/{interview_id}/answers",
        headers=headers,
        json={"answers": [answers[0]]},
    )
    assert repeated.status_code == 200
    assert repeated.json()["progress"] == ready.json()["progress"]
    assert len(repeated.json()["answers"]) == len(ready.json()["answers"])


def test_completion_requires_ready_is_idempotent_and_feeds_prompt_engine(client: TestClient) -> None:
    headers = _auth(client, "complete@example.com")
    interview = _start(client, headers, mode="pro", category="programacao")
    interview_id = interview["id"]
    assert client.post(f"/api/v1/interviews/{interview_id}/complete", headers=headers).status_code == 409

    answers = [{"question_key": question["key"], "value": _value(question)} for question in interview["questions"]]
    assert (
        client.post(
            f"/api/v1/interviews/{interview_id}/answers", headers=headers, json={"answers": answers}
        ).status_code
        == 200
    )
    first = client.post(f"/api/v1/interviews/{interview_id}/complete", headers=headers)
    second = client.post(f"/api/v1/interviews/{interview_id}/complete", headers=headers)
    assert first.status_code == second.status_code == 200
    assert first.json()["prompt_input"] == second.json()["prompt_input"]
    assert first.json()["interview"]["completed_at"] == second.json()["interview"]["completed_at"]
    prompt_input = PromptGenerateRequest.model_validate(first.json()["prompt_input"])
    assert prompt_input.optimize_with_ai is False
    assert prompt_input.category == PromptCategory.PROGRAMMING
    assert prompt_input.context and "stack" in prompt_input.context.lower()

    cannot_answer = client.post(
        f"/api/v1/interviews/{interview_id}/answers",
        headers=headers,
        json={"answers": [answers[0]]},
    )
    assert cannot_answer.status_code == 409


def test_interview_ownership_prevents_idor_and_missing_is_uniform(client: TestClient) -> None:
    owner = _auth(client, "interview-owner@example.com")
    stranger = _auth(client, "interview-stranger@example.com")
    interview = _start(client, owner)
    path = f"/api/v1/interviews/{interview['id']}"
    answer = {"answers": [{"question_key": interview["questions"][0]["key"], "value": "privado"}]}

    assert client.get(path, headers=stranger).status_code == 404
    assert client.post(f"{path}/answers", headers=stranger, json=answer).status_code == 404
    assert client.post(f"{path}/complete", headers=stranger).status_code == 404
    missing = "/api/v1/interviews/00000000-0000-0000-0000-000000000001"
    assert client.get(missing, headers=owner).status_code == 404
