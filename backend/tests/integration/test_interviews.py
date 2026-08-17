from typing import Any

import pytest
from fastapi.testclient import TestClient

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
) -> dict[str, Any]:
    response = client.post(
        "/api/v1/interviews",
        headers=headers,
        json={
            "initial_request": "Quero criar um anúncio para vender um tênis feminino",
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
