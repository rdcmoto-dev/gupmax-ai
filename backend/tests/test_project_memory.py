import pytest

from app.modules.projects.memory import ProjectMemory


def test_milestone_aliases_are_canonicalized_and_empty_is_ignored() -> None:
    assert ProjectMemory.normalize_context(
        "milestone: Definir   posicionamento\nMarco:   \nPúblico: Famílias"
    ) == "Marco: Definir posicionamento\nPúblico: Famílias"


def test_twenty_memory_entries_are_preserved_without_truncation() -> None:
    context = "\n".join(f"Campo {index}: Valor" for index in range(20))
    assert ProjectMemory.normalize_context(context) == context


def test_goal_criteria_and_milestones_coexist_at_their_limits() -> None:
    context = "\n".join(
        ["Objetivo: Lançar campanha"]
        + [f"Critério de sucesso: Critério {index}" for index in range(5)]
        + [f"Marco: Marco {index}" for index in range(5)]
        + [f"Campo {index}: Valor" for index in range(9)]
    )
    assert len(ProjectMemory.normalize_context(context).splitlines()) == 20


def test_manual_completion_is_inline_and_removed_from_prompt_context() -> None:
    context = ProjectMemory.normalize_context(
        "Critério de sucesso: [X] Campanha pronta\nMarco: [x] Publicar campanha"
    )
    assert context == (
        "Critério de sucesso: [x] Campanha pronta\nMarco: [x] Publicar campanha"
    )
    assert ProjectMemory.prompt_context(context, set()) == (
        "Critério de sucesso: Campanha pronta\nMarco: Publicar campanha"
    )


def test_project_review_metadata_is_canonical_and_removed_from_prompt_context() -> None:
    context = ProjectMemory.normalize_context(
        "Público: Restaurantes\nOBSERVAÇÕES FINAIS: Trabalho entregue.\nPROJETO ENCERRADO: SIM"
    )

    assert context == (
        "Público: Restaurantes\n"
        "Conclusão do projeto: Trabalho entregue.\n"
        "Projeto encerrado: sim"
    )
    assert ProjectMemory.prompt_context(context, set()) == "Público: Restaurantes"


@pytest.mark.parametrize(
    "context",
    [
        "Conclusão do projeto: A\nConclusão final: B",
        "Projeto encerrado: sim\nPROJETO ENCERRADO: SIM",
        "Projeto encerrado: não",
        f"Conclusão do projeto: {'a' * 1001}",
    ],
)
def test_project_review_metadata_rejects_invalid_direct_payloads(context: str) -> None:
    with pytest.raises(ValueError):
        ProjectMemory.normalize_context(context)


@pytest.mark.parametrize(
    "context",
    [
        "Objetivo: A\nobjetivo do projeto: B",
        "Marco concluído: Item inexistente",
        "Critério concluído: Item inexistente",
        "\n".join(f"CRITÉRIO DE SUCESSO: Critério {index}" for index in range(6)),
        "\n".join(f"Marco: Marco {index}" for index in range(6)),
        f"Marco: {'x' * 501}",
        "Marco: Publicar campanha\nmilestone:  publicar   campanha ",
        "\n".join(f"Campo {index}: Valor" for index in range(21)),
        "\n".join(f"Campo {index}: {'x' * 800}" for index in range(6)),
    ],
)
def test_invalid_project_memory_context_is_rejected(context: str) -> None:
    with pytest.raises(ValueError):
        ProjectMemory.normalize_context(context)
