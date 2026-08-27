import re
from collections.abc import Iterable

from app.modules.context_engine import ContextEngine
from app.modules.prompt_engine.enums import PromptMode, TargetAI
from app.modules.prompt_engine.schemas import PromptGenerateRequest


class PromptBuilder:
    VISUAL_TERMS = (
        "ambiente", "cenário", "fundo", "interior", "exterior", "paisagem", "mesa", "sala",
        "rua", "praia", "floresta", "estúdio", "pizzaria", "composição", "enquadramento",
        "perspectiva", "câmera", "close-up", "plano", "ângulo", "iluminação", "luz", "cores",
        "paleta", "visual", "fotográfico", "cinematográfico", "realista", "minimalista", "3d",
        "aquarela", "óleo", "mood", "atmosfera", "nitidez", "resolução", "sem texto", "sem logo",
    )
    VIDEO_TERMS = VISUAL_TERMS + (
        "vídeo", "cena", "ação", "movimento", "travelling", "panorâmica", "zoom", "duração",
        "segundo", "minuto", "continuidade", "transição", "áudio", "som", "narração",
    )
    TECHNICAL_TERMS = (
        "código", "software", "aplicação", "api", "banco de dados", "frontend", "backend", "web",
        "mobile", "python", "flutter", "dart", "javascript", "typescript", "react", "fastapi",
        "framework", "biblioteca", "dependência", "arquitetura", "função", "classe", "endpoint",
        "teste", "validação", "compilar", "build", "json", "sql", "bug", "erro", "refator",
    )
    DEFAULT_ROLES = {
        "marketing": "Especialista em marketing e comunicação persuasiva",
        "programacao": "Engenheiro de software experiente",
        "educacao": "Educador especialista no assunto",
        "geral": "Assistente especialista na tarefa solicitada",
    }

    TARGET_SECTIONS = {
        TargetAI.GENERIC: (
            "ROLE", "OBJECTIVE", "CONTEXT", "AUDIENCE", "INSTRUCTIONS", "CONSTRAINTS",
            "OUTPUT FORMAT", "LANGUAGE", "TONE", "ADDITIONAL INFORMATION",
        ),
        TargetAI.CHATGPT: (
            "ROLE", "OBJECTIVE", "CONTEXT", "AUDIENCE", "INSTRUCTIONS", "CONSTRAINTS",
            "OUTPUT FORMAT", "LANGUAGE", "TONE", "ADDITIONAL INFORMATION",
        ),
        TargetAI.CLAUDE: (
            "CONTEXT", "TASK", "INSTRUCTIONS", "CONSTRAINTS", "EXPECTED FORMAT",
            "RELEVANT INFORMATION", "AUDIENCE", "LANGUAGE", "TONE", "ROLE",
        ),
        TargetAI.GEMINI: (
            "OBJECTIVE", "CONTEXT", "INSTRUCTIONS", "PROVIDED DATA", "EXPECTED FORMAT",
            "CONSTRAINTS", "LANGUAGE", "TONE", "AUDIENCE", "ROLE",
        ),
        TargetAI.MIDJOURNEY: (
            "SUBJECT", "ENVIRONMENT", "COMPOSITION", "VISUAL STYLE", "LIGHTING",
            "CAMERA / VIEW", "COLORS", "MOOD", "RELEVANT DETAILS", "VISUAL RESTRICTIONS",
        ),
        TargetAI.IMAGE_GENERATOR: (
            "MAIN SUBJECT", "ENVIRONMENT", "COMPOSITION", "VISUAL STYLE", "LIGHTING",
            "PERSPECTIVE / FRAMING", "COLORS", "IMPORTANT DETAILS", "VISUAL RESTRICTIONS",
        ),
        TargetAI.VIDEO_GENERATOR: (
            "SCENE", "SUBJECT", "ACTION", "ENVIRONMENT", "CAMERA", "MOVEMENT", "LIGHTING",
            "VISUAL STYLE", "TEMPORAL CONTEXT", "CONTINUITY", "RESTRICTIONS",
        ),
        TargetAI.CODING_ASSISTANT: (
            "TECHNICAL ROLE", "OBJECTIVE", "TECHNICAL CONTEXT", "STACK", "REQUIREMENTS",
            "CONSTRAINTS", "EXPECTED BEHAVIOR", "OUTPUT FORMAT", "TESTS / VALIDATION",
            "LANGUAGE", "AUDIENCE", "ADDITIONAL INFORMATION",
        ),
    }

    def build(self, data: PromptGenerateRequest) -> str:
        role = data.role or self.DEFAULT_ROLES.get(data.category.value, self.DEFAULT_ROLES["geral"])
        audience = self._resolved_field(data, "audience", data.audience)
        tone = self._resolved_field(data, "tone", data.tone)
        context = self._resolved_field(data, "context", data.context)
        sections: list[tuple[str, str | None]] = [("ROLE", role), ("OBJECTIVE", data.input)]
        sections.extend((
            ("CONTEXT", context),
            ("AUDIENCE", audience),
        ))
        instructions = data.instructions or self._default_instructions(data.mode)
        sections.append(("INSTRUCTIONS", self._list(instructions)))
        if data.mode == PromptMode.EXPERT or data.constraints:
            sections.append(("CONSTRAINTS", self._list(data.constraints)))
        if data.mode != PromptMode.BASIC or data.output_format:
            sections.append(
                ("OUTPUT FORMAT", data.output_format or "Entregue uma resposta clara, organizada e pronta para uso.")
            )
        sections.extend((("LANGUAGE", data.language), ("TONE", tone)))
        if data.additional_information:
            sections.append(("ADDITIONAL INFORMATION", data.additional_information))
        resolved_context = ContextEngine().render(data)
        if resolved_context:
            sections.append(("STRUCTURED CONTEXT (USER-PROVIDED DATA)", resolved_context))
        if data.target_ai == TargetAI.GENERIC:
            built = self._render(sections)
        else:
            values = self._target_values(data, role, instructions)
            built = self._render(
                (name, values.get(name)) for name in self.TARGET_SECTIONS[data.target_ai]
            )
            if resolved_context:
                built = (
                    f"{built}\n\n## STRUCTURED CONTEXT (USER-PROVIDED DATA)\n"
                    f"{resolved_context}"
                )
        return self._append_previous_result(built, data.previous_result)

    @staticmethod
    def _as_user_data(value: str | None) -> str | None:
        if value is None:
            return None
        return "\n".join(f"> {line}" if line else ">" for line in value.splitlines())

    def _resolved_field(
        self, data: PromptGenerateRequest, key: str, current: str | None
    ) -> str | None:
        smart_value = data.smart_answers.get(key)
        if smart_value and smart_value == current:
            return self._as_user_data(smart_value)
        return current or self._as_user_data(smart_value)

    @staticmethod
    def _append_previous_result(built: str, previous_result: str | None) -> str:
        if not previous_result:
            return built
        quoted = "\n".join(f"> {line}" if line else ">" for line in previous_result.splitlines())
        return (
            f"{built}\n\n## PREVIOUS STEP RESULT (CONTEXT ONLY)\n"
            f"Use somente como referência para executar o objetivo atual.\n\n{quoted}"
        )

    @staticmethod
    def _render(sections: Iterable[tuple[str, str | None]]) -> str:
        return "\n\n".join(f"## {name}\n{value}" for name, value in sections if value)

    def _target_values(self, data: PromptGenerateRequest, role: str, instructions: list[str]) -> dict[str, str | None]:
        listed_instructions = self._list(instructions)
        listed_constraints = self._list(data.constraints)
        default_format = data.output_format or (
            "Entregue uma resposta clara, organizada e pronta para uso."
            if data.mode != PromptMode.BASIC else None
        )
        common = {
            "ROLE": role,
            "OBJECTIVE": data.input,
            "CONTEXT": self._resolved_field(data, "context", data.context),
            "AUDIENCE": self._resolved_field(data, "audience", data.audience),
            "INSTRUCTIONS": listed_instructions,
            "CONSTRAINTS": listed_constraints, "OUTPUT FORMAT": default_format,
            "LANGUAGE": data.language,
            "TONE": self._resolved_field(data, "tone", data.tone),
            "ADDITIONAL INFORMATION": data.additional_information,
        }
        values = dict(common)
        values.update({
            "TASK": data.input, "EXPECTED FORMAT": default_format,
            "RELEVANT INFORMATION": data.additional_information,
            "PROVIDED DATA": data.additional_information,
            "SUBJECT": data.input, "MAIN SUBJECT": data.input,
            "SCENE": data.input,
        })
        if data.target_ai in {TargetAI.MIDJOURNEY, TargetAI.IMAGE_GENERATOR}:
            visual_instructions = self._matching_items(data.instructions, self.VISUAL_TERMS)
            visual_constraints = self._matching_items(data.constraints, self.VISUAL_TERMS)
            explicit_visual = self._visual_facts(data.input)
            values.update({
                "ENVIRONMENT": self._compatible(data.context, self.VISUAL_TERMS)
                or explicit_visual["environment"],
                "COMPOSITION": self._compatible(data.output_format, self.VISUAL_TERMS)
                or self._visual_composition(data.input, data.mode),
                "VISUAL STYLE": self._compatible(data.tone, self.VISUAL_TERMS)
                or self._visual_style(data.input),
                "MOOD": self._compatible(data.tone, self.VISUAL_TERMS) or explicit_visual["mood"],
                "RELEVANT DETAILS": self._combine(
                    explicit_visual["details"],
                    self._list(visual_instructions),
                    self._compatible(data.additional_information, self.VISUAL_TERMS),
                ),
                "IMPORTANT DETAILS": self._combine(
                    explicit_visual["details"],
                    self._list(visual_instructions),
                    self._compatible(data.additional_information, self.VISUAL_TERMS),
                ),
                "VISUAL RESTRICTIONS": self._list(visual_constraints),
            })
        elif data.target_ai == TargetAI.VIDEO_GENERATOR:
            video_instructions = self._matching_items(data.instructions, self.VIDEO_TERMS)
            video_constraints = self._matching_items(data.constraints, self.VIDEO_TERMS)
            explicit_video = self._video_facts(data.input)
            values.update({
                "SCENE": explicit_video["scene"],
                "SUBJECT": explicit_video["subject"],
                "ENVIRONMENT": self._compatible(data.context, self.VIDEO_TERMS)
                or explicit_video["environment"],
                "VISUAL STYLE": self._compatible(data.tone, self.VIDEO_TERMS),
                "TEMPORAL CONTEXT": explicit_video["duration"]
                or self._compatible(data.additional_information, ("duração", "segundo", "minuto")),
                "CONTINUITY": self._compatible(data.output_format, ("continuidade", "transição", "cena", "sequência")),
                "RESTRICTIONS": self._list(video_constraints),
                "ACTION": self._combine(explicit_video["action"], self._list(video_instructions)),
            })
        elif data.target_ai == TargetAI.CODING_ASSISTANT:
            technical_instructions = self._matching_items(data.instructions, self.TECHNICAL_TERMS)
            technical_constraints = self._matching_items(data.constraints, self.TECHNICAL_TERMS)
            values.update({
                "TECHNICAL ROLE": self._compatible(data.role, self.TECHNICAL_TERMS)
                or "Engenheiro de software experiente",
                "TECHNICAL CONTEXT": self._compatible(data.context, self.TECHNICAL_TERMS),
                "STACK": self._coding_stack(data.input),
                "REQUIREMENTS": self._combine(data.input, self._list(technical_instructions)),
                "CONSTRAINTS": self._list(technical_constraints),
                "EXPECTED BEHAVIOR": self._compatible(data.output_format, self.TECHNICAL_TERMS),
                "OUTPUT FORMAT": self._compatible(data.output_format, self.TECHNICAL_TERMS),
                "TESTS / VALIDATION": self._compatible(
                    data.additional_information, ("teste", "valid", "lint", "análise")
                ),
                "AUDIENCE": None,
                "ADDITIONAL INFORMATION": None,
            })
        return values

    @classmethod
    def _visual_facts(cls, value: str) -> dict[str, str | None]:
        details = cls._explicit_segments(value)
        environments = [item for item in details if cls._compatible(item, cls.VISUAL_TERMS)]
        mood_terms = ("elegante", "convidativo", "dramático", "alegre", "sombrio", "acolhedor", "sereno")
        mood = next((term.capitalize() for term in mood_terms if term in value.casefold()), None)
        return {
            "environment": "; ".join(environments) or None,
            "details": "; ".join(details) or None,
            "mood": mood,
        }

    @staticmethod
    def _explicit_segments(value: str) -> list[str]:
        compact = " ".join(value.strip().rstrip(".").split())
        compact = re.sub(
            r"(?i)^criar\s+(?:uma?\s+)?(?:imagem|foto|vídeo)\s+(?:publicitária?\s+)?(?:de\s+)?",
            "",
            compact,
        )
        return [
            segment.strip(" ,")
            for segment in re.split(r"(?i)\s+sobre\s+|,?\s+em\s+", compact)
            if segment.strip(" ,")
        ]

    @staticmethod
    def _visual_composition(value: str, mode: PromptMode) -> str:
        base = "Composição visual com o assunto principal em destaque"
        if "publicit" in value.casefold():
            base = "Composição publicitária com o produto em destaque e foco visual no assunto principal"
        if mode == PromptMode.EXPERT:
            return f"{base}, hierarquia visual clara e equilíbrio entre assunto e ambiente."
        return f"{base}."

    @staticmethod
    def _visual_style(value: str) -> str:
        folded = value.casefold()
        if any(term in folded for term in ("pizza", "comida", "prato", "restaurante", "gastron")):
            return "Fotografia gastronômica realista"
        if "publicit" in folded:
            return "Fotografia publicitária realista"
        return "Representação visual clara e coerente com o pedido"

    @classmethod
    def _video_facts(cls, value: str) -> dict[str, str | None]:
        duration = re.search(r"(?i)\b(\d{1,3}\s*(?:segundos?|minutos?))\b", value)
        visual = cls._visual_facts(value)
        showing_match = re.search(r"(?is)\bmostrando\s+(.+?)[.]?$", value.strip())
        showing = showing_match.group(1).strip() if showing_match else ""
        action_start = re.search(r"(?i)\b(?:sendo|ficando|começando|terminando)\b", showing)
        subject = showing[: action_start.start()].strip(" ,") if action_start else showing or None
        action_text = showing[action_start.start() :].strip(" ,") if action_start else None
        if action_text:
            for environment_start in re.finditer(r"(?i)\s+em\s+", action_text):
                following = action_text[environment_start.end() :]
                phrase = re.split(r",|\s+em\s+|\s+e\s+", following, maxsplit=1, flags=re.IGNORECASE)[0]
                if cls._compatible(phrase, cls.VISUAL_TERMS):
                    action_text = action_text[: environment_start.start()].strip(" ,")
                    break
        actions = cls._action_sequence(action_text)
        environment = visual["environment"]
        kind = "Vídeo publicitário" if "publicit" in value.casefold() else "Vídeo"
        if showing:
            scene = cls._combine(
                f"{kind} de {subject}" if subject else kind,
                f"Ambiente: {environment}" if environment else None,
            )
        else:
            scene = value
        return {
            "duration": duration.group(1) if duration else None,
            "action": actions,
            "environment": environment,
            "subject": subject if showing else None,
            "scene": scene,
        }

    @staticmethod
    def _action_sequence(value: str | None) -> str | None:
        if value is None:
            return None
        parts = re.split(r",\s*|\s+e\s+(?=(?:sendo\s+)?\w+)", value)
        actions = [part.strip(" ,") for part in parts if part.strip(" ,")]
        return "; ".join(actions) or None

    @classmethod
    def _coding_stack(cls, value: str) -> str | None:
        labels = {
            "python": "Python", "fastapi": "FastAPI", "flutter": "Flutter", "dart": "Dart",
            "javascript": "JavaScript", "typescript": "TypeScript", "react": "React",
        }
        folded = value.casefold()
        found = [label for term, label in labels.items() if term in folded]
        return ", ".join(found) or None

    @staticmethod
    def _compatible(value: str | None, terms: tuple[str, ...]) -> str | None:
        if value is None:
            return None
        folded = value.casefold()
        return value if any(term in folded for term in terms) else None

    @classmethod
    def _matching_items(cls, items: list[str], terms: tuple[str, ...]) -> list[str]:
        return [item for item in items if cls._compatible(item, terms) is not None]

    @staticmethod
    def _combine(*values: str | None) -> str | None:
        present = [value for value in values if value]
        return "\n".join(present) if present else None

    @staticmethod
    def _default_instructions(mode: PromptMode) -> list[str]:
        instructions = ["Atenda ao objetivo com informações específicas e acionáveis."]
        if mode != PromptMode.BASIC:
            instructions.append("Adapte vocabulário, profundidade e abordagem ao público e ao contexto.")
        if mode == PromptMode.EXPERT:
            instructions.append("Revise consistência, precisão e aderência a todas as restrições antes de responder.")
        return instructions

    @staticmethod
    def _list(items: list[str]) -> str | None:
        return "\n".join(f"- {item}" for item in items) if items else None
