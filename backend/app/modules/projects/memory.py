import re
import unicodedata


class ProjectMemory:
    """Keeps explicitly saved Project context subordinate to current input."""

    LABEL_KEYS = {
        "objetivo": "objective",
        "produto": "product",
        "produto servico": "product",
        "publico": "audience",
        "publico alvo": "audience",
        "plataforma": "platform",
        "canal": "channel",
        "tom": "tone",
        "tone": "tone",
        "requisitos": "requirements",
        "restricoes": "constraints",
        "tecnologias": "stack",
        "stack": "stack",
        "observacoes": "additional_information",
        "informacao": "context",
        "informacoes importantes": "context",
    }
    VARIABLE_KEYS = {
        "produto": "product",
        "servico": "product",
        "publico": "audience",
        "publico_alvo": "audience",
        "plataforma": "platform",
        "canal": "channel",
        "tom": "tone",
        "tone": "tone",
        "contexto": "context",
        "requisitos": "requirements",
        "restricoes": "constraints",
        "stack": "stack",
    }

    @classmethod
    def semantic_keys(cls, variable_values: dict[str, str]) -> set[str]:
        return {
            key
            for name in variable_values
            if (key := cls.VARIABLE_KEYS.get(cls._fold(name))) is not None
        }

    @classmethod
    def semantic_values(cls, value: str) -> dict[str, str]:
        values: dict[str, str] = {}
        for line in value.splitlines():
            label, separator, raw_value = line.partition(":")
            key = cls.LABEL_KEYS.get(cls._fold(label)) if separator else None
            normalized = raw_value.strip()
            if key is not None and normalized:
                values[key] = normalized
        return values

    @classmethod
    def without_overridden(cls, value: str, overridden: set[str]) -> str | None:
        aliases = set(overridden)
        if "platform" in aliases:
            aliases.add("channel")
        if "channel" in aliases:
            aliases.add("platform")
        kept: list[str] = []
        for line in value.splitlines():
            label, separator, _ = line.partition(":")
            key = cls.LABEL_KEYS.get(cls._fold(label)) if separator else None
            if key is None or key not in aliases:
                kept.append(line.strip())
        result = "\n".join(line for line in kept if line).strip()
        return result or None

    @staticmethod
    def _fold(value: str) -> str:
        decomposed = unicodedata.normalize("NFKD", value.casefold())
        plain = "".join(char for char in decomposed if not unicodedata.combining(char))
        return " ".join(re.sub(r"[^a-z0-9]+", " ", plain).split())
