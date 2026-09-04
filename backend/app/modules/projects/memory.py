import re
import unicodedata


class ProjectMemory:
    """Keeps explicitly saved Project context subordinate to current input."""

    MAX_ENTRIES = 20
    MAX_OBJECTIVES = 1
    MAX_SUCCESS_CRITERIA = 5
    MAX_MILESTONES = 5
    MAX_LABEL_LENGTH = 80
    MAX_VALUE_LENGTH = 1000
    MAX_MILESTONE_LENGTH = 500
    MAX_CONTEXT_LENGTH = 4000
    MILESTONE_LABEL = "Marco"
    OBJECTIVE_LABELS = {"objetivo", "objetivo do projeto"}
    SUCCESS_CRITERION_LABELS = {"criterio de sucesso", "criterios de sucesso"}

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

    @classmethod
    def normalize_context(cls, value: str | None) -> str | None:
        if value is None or not value.strip():
            return None
        lines: list[str] = []
        objective_count = 0
        success_criterion_count = 0
        milestone_count = 0
        milestone_signatures: set[str] = set()
        for raw_line in value.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            label, separator, raw_value = line.partition(":")
            if separator:
                normalized_label = " ".join(label.split())
                normalized_value = raw_value.strip()
                if not normalized_label or not normalized_value:
                    continue
                if len(normalized_label) > cls.MAX_LABEL_LENGTH:
                    raise ValueError("Cada rótulo da memória deve ter no máximo 80 caracteres.")
                if len(normalized_value) > cls.MAX_VALUE_LENGTH:
                    raise ValueError("Cada informação do projeto deve ter no máximo 1.000 caracteres.")
                folded_label = cls._fold(normalized_label)
                if folded_label in cls.OBJECTIVE_LABELS:
                    objective_count += 1
                    if objective_count > cls.MAX_OBJECTIVES:
                        raise ValueError("Use no máximo 1 objetivo do projeto.")
                if folded_label in cls.SUCCESS_CRITERION_LABELS:
                    success_criterion_count += 1
                    if success_criterion_count > cls.MAX_SUCCESS_CRITERIA:
                        raise ValueError("Use no máximo 5 critérios de sucesso.")
                if folded_label not in {"marco", "milestone"}:
                    lines.append(f"{normalized_label}: {normalized_value}")
                    continue
                milestone = " ".join(normalized_value.split())
                if len(milestone) > cls.MAX_MILESTONE_LENGTH:
                    raise ValueError("Cada marco deve ter no máximo 500 caracteres.")
                signature = cls._fold(milestone)
                if signature in milestone_signatures:
                    raise ValueError("Não adicione marcos duplicados.")
                milestone_signatures.add(signature)
                milestone_count += 1
                if milestone_count > cls.MAX_MILESTONES:
                    raise ValueError("Use no máximo 5 marcos.")
                lines.append(f"{cls.MILESTONE_LABEL}: {milestone}")
            else:
                if len(line) > cls.MAX_VALUE_LENGTH:
                    raise ValueError("Cada informação do projeto deve ter no máximo 1.000 caracteres.")
                lines.append(line)
        if len(lines) > cls.MAX_ENTRIES:
            raise ValueError("O contexto do projeto aceita no máximo 20 entradas.")
        result = "\n".join(lines)
        if len(result) > cls.MAX_CONTEXT_LENGTH:
            raise ValueError("O contexto do projeto deve ter no máximo 4.000 caracteres.")
        return result or None

    @staticmethod
    def _fold(value: str) -> str:
        decomposed = unicodedata.normalize("NFKD", value.casefold())
        plain = "".join(char for char in decomposed if not unicodedata.combining(char))
        return " ".join(re.sub(r"[^a-z0-9]+", " ", plain).split())
