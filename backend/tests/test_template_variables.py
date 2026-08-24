import pytest

from app.modules.prompt_templates.variables import detect_variables, resolve_text, validate_variable_count


@pytest.mark.parametrize(
    ("content", "expected"),
    [
        ("{produto}", ["produto"]),
        ("{publico_alvo} {cidade1}", ["publico_alvo", "cidade1"]),
        ("{Produto} e novamente {produto}", ["produto"]),
        ("{} {1produto} {produto nome} {produto-preco} {{produto}}", []),
        ('{"name":"value"}', []),
        ('{"key": value}', []),
        ("body { color: red; }", []),
        ("const value = {'name': 'Ricardo'}; use {resource_name}", ["resource_name"]),
    ],
)
def test_detect_variables_is_strict_and_code_safe(content: str, expected: list[str]) -> None:
    assert detect_variables(content) == expected


def test_resolve_is_plain_deterministic_string_replacement() -> None:
    template = "Crie para {produto}. Destaque {PRODUTO} no {canal}."
    assert resolve_text(template, {"produto": "Pizza artesanal", "canal": "Instagram"}) == (
        "Crie para Pizza artesanal. Destaque Pizza artesanal no Instagram."
    )


def test_maximum_twenty_unique_variables() -> None:
    assert len(validate_variable_count([f"campo{index}" for index in range(20)])) == 20
    with pytest.raises(ValueError, match="at most 20"):
        validate_variable_count([f"campo{index}" for index in range(21)])
