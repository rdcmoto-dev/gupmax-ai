from app.modules.prompt_engine.enums import PromptMode
from app.modules.prompt_engine.schemas import PromptGenerateRequest


class PromptBuilder:
    DEFAULT_ROLES = {
        "marketing": "Especialista em marketing e comunicação persuasiva",
        "programacao": "Engenheiro de software experiente",
        "educacao": "Educador especialista no assunto",
        "geral": "Assistente especialista na tarefa solicitada",
    }

    def build(self, data: PromptGenerateRequest) -> str:
        role = data.role or self.DEFAULT_ROLES.get(data.category.value, self.DEFAULT_ROLES["geral"])
        sections: list[tuple[str, str | None]] = [("ROLE", role), ("OBJECTIVE", data.input)]
        sections.extend((("CONTEXT", data.context), ("AUDIENCE", data.audience)))
        instructions = data.instructions or self._default_instructions(data.mode)
        sections.append(("INSTRUCTIONS", self._list(instructions)))
        if data.mode == PromptMode.EXPERT or data.constraints:
            sections.append(("CONSTRAINTS", self._list(data.constraints)))
        if data.mode != PromptMode.BASIC or data.output_format:
            sections.append(
                ("OUTPUT FORMAT", data.output_format or "Entregue uma resposta clara, organizada e pronta para uso.")
            )
        sections.extend((("LANGUAGE", data.language), ("TONE", data.tone)))
        if data.additional_information:
            sections.append(("ADDITIONAL INFORMATION", data.additional_information))
        return "\n\n".join(f"## {name}\n{value}" for name, value in sections if value)

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
