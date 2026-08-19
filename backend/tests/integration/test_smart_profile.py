from fastapi.testclient import TestClient


def auth(client: TestClient, email: str) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "full_name": "Profile User", "password": "SecurePassword123!"},
    )
    assert response.status_code == 201
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def profile_payload(**overrides):
    return {
        "is_enabled": True,
        "default_language": "pt-BR",
        "default_tone": "profissional",
        "default_audience": "empresários",
        "default_channel": "Instagram",
        "default_output_format": "Texto curto",
        "business_context": "Negócio local",
        "default_constraints": ["Não invente dados"],
        "default_instructions": ["Seja objetivo"],
        **overrides,
    }


def test_profile_empty_upsert_update_delete_and_ownership(client: TestClient) -> None:
    first = auth(client, "smart-first@example.com")
    second = auth(client, "smart-second@example.com")
    empty = client.get("/api/v1/profile/prompt-preferences", headers=first)
    assert empty.status_code == 200
    assert empty.json()["is_enabled"] is False
    saved = client.put("/api/v1/profile/prompt-preferences", headers=first, json=profile_payload())
    assert saved.status_code == 200
    assert saved.json()["default_tone"] == "profissional"
    assert client.get("/api/v1/profile/prompt-preferences", headers=second).json()["default_tone"] is None
    updated = client.put(
        "/api/v1/profile/prompt-preferences",
        headers=first,
        json=profile_payload(default_tone="casual", default_audience="  "),
    )
    assert updated.json()["default_tone"] == "casual"
    assert updated.json()["default_audience"] is None
    assert client.delete("/api/v1/profile/prompt-preferences", headers=first).status_code == 204
    assert client.get("/api/v1/profile/prompt-preferences", headers=first).json()["default_tone"] is None


def test_profile_fallback_explicit_request_precedence_and_disabled(client: TestClient) -> None:
    headers = auth(client, "smart-precedence@example.com")
    client.put("/api/v1/profile/prompt-preferences", headers=headers, json=profile_payload())
    fallback = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={"input": "Crie uma apresentação institucional.", "category": "negocios", "mode": "pro"},
    )
    assert fallback.status_code == 201, fallback.text
    text = fallback.json()["generated_prompt"]
    assert "empresários" in text and "profissional" in text and "Negócio local" in text

    explicit = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "input": "Crie um anúncio casual em espanhol para empreendedores no TikTok.",
            "category": "marketing",
            "mode": "pro",
        },
    )
    assert explicit.status_code == 201
    body = explicit.json()
    assert body["language"] == "es"
    assert body["tone"] == "casual"
    assert "empreendedores" in body["generated_prompt"]
    assert "TikTok" in body["generated_prompt"]

    client.put(
        "/api/v1/profile/prompt-preferences", headers=headers, json=profile_payload(is_enabled=False)
    )
    disabled = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={"input": "Crie uma apresentação institucional.", "category": "negocios", "mode": "pro"},
    ).json()["generated_prompt"]
    assert "empresários" not in disabled


def test_basic_profile_applies_all_preferences_without_financial_effects(client: TestClient) -> None:
    headers = auth(client, "smart-basic@example.com")
    saved_profile = profile_payload(
        default_audience="donos de pequenos negócios",
        default_output_format="lista objetiva",
        business_context="Pequena empresa brasileira que vende produtos e serviços pela internet.",
        default_constraints=["Use linguagem clara e prática."],
        default_instructions=["Priorize recomendações aplicáveis e objetivas."],
    )
    assert client.put(
        "/api/v1/profile/prompt-preferences", headers=headers, json=saved_profile
    ).status_code == 200
    wallet_before = client.get("/api/v1/credits/wallet", headers=headers).json()
    usage_before = client.get("/api/v1/billing/usage", headers=headers).json()["total"]
    ledger_before = client.get("/api/v1/credits/transactions", headers=headers).json()["total"]

    response = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "input": "Criar uma campanha para divulgar uma pizzaria.",
            "category": "marketing",
            "mode": "basic",
            "optimize_with_ai": False,
        },
    )

    assert response.status_code == 201, response.text
    prompt = response.json()["generated_prompt"]
    for expected in (
        "pt-BR",
        "profissional",
        "donos de pequenos negócios",
        "Instagram",
        "lista objetiva",
        "Pequena empresa brasileira que vende produtos e serviços pela internet.",
        "Use linguagem clara e prática.",
        "Priorize recomendações aplicáveis e objetivas.",
    ):
        assert expected in prompt
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == wallet_before
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == usage_before
    assert client.get("/api/v1/credits/transactions", headers=headers).json()["total"] == ledger_before


def test_basic_explicit_audience_and_context_override_profile(client: TestClient) -> None:
    headers = auth(client, "smart-basic-precedence@example.com")
    saved_profile = profile_payload(
        default_audience="donos de pequenos negócios",
        business_context="Pequena empresa brasileira que vende produtos e serviços pela internet.",
    )
    saved = client.put(
        "/api/v1/profile/prompt-preferences", headers=headers, json=saved_profile
    ).json()

    response = client.post(
        "/api/v1/prompts/generate",
        headers=headers,
        json={
            "input": "Criar uma campanha para divulgar uma pizzaria.",
            "category": "marketing",
            "mode": "basic",
            "audience": "famílias da região",
            "context": "Campanha de inauguração da nova unidade.",
            "optimize_with_ai": False,
        },
    )

    assert response.status_code == 201, response.text
    prompt = response.json()["generated_prompt"]
    assert "famílias da região" in prompt
    assert "Campanha de inauguração da nova unidade." in prompt
    assert "donos de pequenos negócios" not in prompt
    assert "Pequena empresa brasileira que vende produtos e serviços pela internet." not in prompt
    persisted = client.get("/api/v1/profile/prompt-preferences", headers=headers).json()
    assert persisted == saved


def test_profile_reduces_redundant_interview_questions_without_financial_effects(client: TestClient) -> None:
    headers = auth(client, "smart-interview@example.com")
    client.put("/api/v1/profile/prompt-preferences", headers=headers, json=profile_payload())
    wallet_before = client.get("/api/v1/credits/wallet", headers=headers).json()
    interview = client.post(
        "/api/v1/interviews",
        headers=headers,
        json={"initial_request": "Crie um anúncio.", "mode": "pro", "category": "marketing"},
    )
    assert interview.status_code == 201
    keys = {question["key"] for question in interview.json()["questions"]}
    assert not {"audience", "tone", "channel"} & keys
    assert client.get("/api/v1/billing/usage", headers=headers).json()["total"] == 0
    assert client.get("/api/v1/credits/wallet", headers=headers).json() == wallet_before


def test_interview_explicit_form_fields_override_profile(client: TestClient) -> None:
    headers = auth(client, "smart-interview-precedence@example.com")
    client.put("/api/v1/profile/prompt-preferences", headers=headers, json=profile_payload())

    response = client.post(
        "/api/v1/interviews",
        headers=headers,
        json={
            "initial_request": "Crie um anúncio com CTA: compre agora.",
            "mode": "pro",
            "category": "marketing",
            "known_fields": {
                "input": "Crie um anúncio com CTA: compre agora.",
                "mode": "pro",
                "category": "marketing",
                "language": "es",
                "tone": "casual",
                "audience": "famílias da região",
                "context": "Campanha de inauguração.",
            },
        },
    )

    assert response.status_code == 201, response.text
    interview = response.json()
    assert interview["status"] == "ready"
    completed = client.post(
        f"/api/v1/interviews/{interview['id']}/complete", headers=headers
    )
    assert completed.status_code == 200, completed.text
    prompt_input = completed.json()["prompt_input"]
    assert prompt_input["language"] == "es"
    assert prompt_input["tone"] == "casual"
    assert prompt_input["audience"] == "famílias da região"
    assert "Campanha de inauguração." in prompt_input["context"]
    assert "Negócio local" not in prompt_input["context"]


def test_profile_limits_are_validated(client: TestClient) -> None:
    headers = auth(client, "smart-limits@example.com")
    assert (
        client.put(
            "/api/v1/profile/prompt-preferences",
            headers=headers,
            json=profile_payload(business_context="x" * 4001),
        ).status_code
        == 422
    )
