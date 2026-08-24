import re
from collections.abc import Iterable, Mapping

from fastapi import HTTPException, status

MAX_TEMPLATE_VARIABLES = 20
MAX_VARIABLE_VALUE_LENGTH = 4_000
VARIABLE_NAME_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_]{0,63}$")
VARIABLE_PATTERN = re.compile(r"(?<!\{)\{([A-Za-z][A-Za-z0-9_]{0,63})\}(?!\})")

_LABELS = {
    "publico": "Público",
    "publico_alvo": "Público alvo",
    "servico": "Serviço",
}


def variable_label(name: str) -> str:
    normalized = name.casefold()
    return _LABELS.get(normalized, normalized.replace("_", " ").capitalize())


def detect_variables(*contents: str | None) -> list[str]:
    variables: list[str] = []
    seen: set[str] = set()
    for content in contents:
        for match in VARIABLE_PATTERN.finditer(content or ""):
            name = match.group(1).casefold()
            if name not in seen:
                seen.add(name)
                variables.append(name)
    return variables


def detect_template_variables(template: object) -> list[str]:
    values: list[str | None] = [
        getattr(template, "template_content", None),
        getattr(template, "base_input", None),
        getattr(template, "tone", None),
        getattr(template, "audience", None),
        getattr(template, "context", None),
        getattr(template, "output_format", None),
        getattr(template, "additional_information", None),
    ]
    values.extend(getattr(template, "instructions", []) or [])
    values.extend(getattr(template, "constraints", []) or [])
    return detect_variables(*values)


def validate_variable_count(names: Iterable[str]) -> list[str]:
    values = list(names)
    if len(values) > MAX_TEMPLATE_VARIABLES:
        raise ValueError(f"templates support at most {MAX_TEMPLATE_VARIABLES} variables")
    return values


def resolve_text(content: str | None, values: Mapping[str, str]) -> str | None:
    if content is None:
        return None
    normalized = {name.casefold(): value for name, value in values.items()}
    return VARIABLE_PATTERN.sub(lambda match: normalized[match.group(1).casefold()], content)


def validate_and_resolve(template: object, values: Mapping[str, str]) -> dict[str, object]:
    variables = validate_variable_count(detect_template_variables(template))
    normalized = {name.casefold(): value.strip() for name, value in values.items()}
    unknown = sorted(set(normalized) - set(variables))
    if unknown:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail="Unknown template variable")
    for name in variables:
        value = normalized.get(name, "")
        if not value:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail=f"Preencha {variable_label(name)}.",
            )
        if len(value) > MAX_VARIABLE_VALUE_LENGTH:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="Template variable is too long",
            )
    return {
        "input": resolve_text(template.base_input, normalized),
        "language": resolve_text(template.language, normalized),
        "tone": resolve_text(template.tone, normalized),
        "audience": resolve_text(template.audience, normalized),
        "context": resolve_text(template.context, normalized),
        "output_format": resolve_text(template.output_format, normalized),
        "additional_information": resolve_text(template.additional_information, normalized),
        "instructions": [resolve_text(item, normalized) for item in template.instructions],
        "constraints": [resolve_text(item, normalized) for item in template.constraints],
    }
