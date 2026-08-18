from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.modules.prompt_engine.enums import PromptCategory, PromptMode
from app.modules.prompt_engine.quality import PromptQualityEvaluator


def prompt(text: str, *, mode: PromptMode = PromptMode.BASIC, category: PromptCategory = PromptCategory.GENERAL):
    return SimpleNamespace(id=uuid4(), generated_prompt=text, mode=mode, category=category)


def test_score_is_bounded_repeatable_and_richer_prompt_scores_higher() -> None:
    evaluator = PromptQualityEvaluator()
    simple = prompt("## OBJECTIVE\nCrie um anúncio.", category=PromptCategory.MARKETING)
    complete = prompt(
        """## ROLE
Especialista em marketing

## OBJECTIVE
Crie um anúncio curto para Instagram.

## CONTEXT
Promoção de uma pizzaria local.

## AUDIENCE
Mulheres e homens de 18 a 35 anos.

## INSTRUCTIONS
- Destaque o benefício e inclua CTA para compra.

## OUTPUT FORMAT
Legenda curta para Instagram.

## CONSTRAINTS
- Não invente preços.

## LANGUAGE
pt-BR

## TONE
Persuasivo""",
        category=PromptCategory.MARKETING,
    )
    first = evaluator.evaluate(simple)
    second = evaluator.evaluate(simple)
    rich = evaluator.evaluate(complete)
    assert 0 <= first.score <= 100
    assert first == second
    assert rich.score > first.score
    assert first.improvements and first.suggestions
    assert rich.strengths


@pytest.mark.parametrize("mode", list(PromptMode))
def test_score_adapts_to_every_mode(mode: PromptMode) -> None:
    result = PromptQualityEvaluator().evaluate(prompt("## OBJECTIVE\nCrie uma resposta clara.", mode=mode))
    assert 0 <= result.score <= 100
    assert len(result.criteria) == 10
    assert sum(item.max_score for item in result.criteria) == 100


@pytest.mark.parametrize("category", list(PromptCategory))
def test_score_supports_every_category(category: PromptCategory) -> None:
    result = PromptQualityEvaluator().evaluate(
        prompt("## OBJECTIVE\nCrie um resultado específico e acionável.\n\n## LANGUAGE\npt-BR", category=category)
    )
    assert result.prompt_id
    assert 0 <= result.score <= 100
