import re
from dataclasses import dataclass

from app.modules.prompt_engine.enums import PromptCategory, PromptMode
from app.modules.prompt_engine.model import Prompt
from app.modules.prompt_engine.schemas import PromptQualityCriterion, PromptQualityResponse


@dataclass(frozen=True)
class _Criterion:
    key: str
    label: str
    section: str | None


class PromptQualityEvaluator:
    """Avalia qualidade estrutural sem executar o conteúdo nem chamar providers."""

    CRITERIA = (
        _Criterion("objective", "Objetivo", "OBJECTIVE"),
        _Criterion("context", "Contexto", "CONTEXT"),
        _Criterion("audience", "Público", "AUDIENCE"),
        _Criterion("instructions", "Instruções", "INSTRUCTIONS"),
        _Criterion("clarity", "Clareza", None),
        _Criterion("output_format", "Formato de saída", "OUTPUT FORMAT"),
        _Criterion("constraints", "Restrições", "CONSTRAINTS"),
        _Criterion("tone", "Tom", "TONE"),
        _Criterion("language", "Idioma", "LANGUAGE"),
        _Criterion("specificity", "Especificidade", None),
    )
    WEIGHTS = {
        PromptMode.BASIC: (25, 5, 5, 15, 15, 5, 5, 8, 7, 10),
        PromptMode.PRO: (18, 12, 12, 16, 10, 8, 6, 7, 5, 6),
        PromptMode.EXPERT: (14, 13, 11, 15, 8, 10, 10, 5, 4, 10),
    }
    CATEGORY_TERMS = {
        PromptCategory.MARKETING: ("público", "instagram", "facebook", "whatsapp", "cta", "compra", "tom"),
        PromptCategory.SALES: ("cliente", "oferta", "benefício", "objeção", "cta", "compra"),
        PromptCategory.SOCIAL_MEDIA: ("instagram", "facebook", "tiktok", "linkedin", "post", "cta"),
        PromptCategory.ECOMMERCE: ("produto", "benefício", "preço", "conversão", "cta", "descrição"),
        PromptCategory.PROGRAMMING: ("stack", "react", "flutter", "api", "funcionalidade", "restrição", "formato"),
        PromptCategory.BUSINESS: ("objetivo", "mercado", "cliente", "estratégia", "resultado"),
        PromptCategory.EDUCATION: ("aluno", "nível", "aprendizagem", "exemplo", "avaliação"),
        PromptCategory.WRITING: ("gênero", "público", "tom", "estrutura", "extensão"),
        PromptCategory.IMAGE: ("estilo", "composição", "dimensão", "formato", "iluminação"),
        PromptCategory.VIDEO: ("plataforma", "duração", "roteiro", "estilo", "público"),
        PromptCategory.PRODUCTIVITY: ("prazo", "prioridade", "etapa", "resultado", "formato"),
        PromptCategory.GENERAL: ("objetivo", "contexto", "público", "formato", "restrição"),
    }
    SECTION_ALIASES = {
        "OBJECTIVE": ("TASK", "SUBJECT", "MAIN SUBJECT", "SCENE"),
        "CONTEXT": ("TECHNICAL CONTEXT", "ENVIRONMENT"),
        "INSTRUCTIONS": ("REQUIREMENTS", "ACTION"),
        "OUTPUT FORMAT": ("EXPECTED FORMAT", "EXPECTED BEHAVIOR", "COMPOSITION"),
        "CONSTRAINTS": ("RESTRICTIONS", "VISUAL RESTRICTIONS"),
        "TONE": ("MOOD", "VISUAL STYLE"),
    }

    def evaluate(self, prompt: Prompt) -> PromptQualityResponse:
        sections = self._sections(prompt.generated_prompt)
        weights = self.WEIGHTS[prompt.mode]
        results: list[PromptQualityCriterion] = []
        for criterion, maximum in zip(self.CRITERIA, weights, strict=True):
            ratio = self._ratio(criterion.key, criterion.section, prompt, sections)
            score = round(maximum * ratio)
            status = "good" if ratio >= 0.75 else "partial" if ratio >= 0.4 else "missing"
            results.append(
                PromptQualityCriterion(
                    key=criterion.key,
                    label=criterion.label,
                    score=score,
                    max_score=maximum,
                    status=status,
                    feedback=self._feedback(criterion.label, status),
                )
            )
        total = sum(item.score for item in results)
        strengths = [f"{item.label} está bem definido." for item in results if item.status == "good"][:4]
        weak = [item for item in results if item.status != "good"]
        improvements = [f"Detalhe melhor: {item.label.lower()}." for item in weak[:4]]
        suggestions = [self._suggestion(item.key) for item in weak[:4]]
        return PromptQualityResponse(
            prompt_id=prompt.id,
            score=total,
            rating=self._rating(total),
            criteria=results,
            strengths=strengths,
            improvements=improvements,
            suggestions=suggestions,
        )

    @staticmethod
    def _sections(text: str) -> dict[str, str]:
        matches = list(re.finditer(r"(?m)^##\s+([^\n]+)\s*$", text))
        sections: dict[str, str] = {}
        for index, match in enumerate(matches):
            end = matches[index + 1].start() if index + 1 < len(matches) else None
            sections[match.group(1).strip().upper()] = text[match.end() : end].strip()
        return sections

    def _ratio(self, key: str, section: str | None, prompt: Prompt, sections: dict[str, str]) -> float:
        text = prompt.generated_prompt.lower()
        if key == "clarity":
            return 1.0 if len(prompt.generated_prompt.split()) >= 20 and "## " in prompt.generated_prompt else 0.6
        if key == "specificity":
            hits = sum(term in text for term in self.CATEGORY_TERMS[prompt.category])
            return min(1.0, 0.35 + hits * 0.18)
        names = (section or "", *self.SECTION_ALIASES.get(section or "", ()))
        value = next((sections[name].strip() for name in names if sections.get(name, "").strip()), "")
        if not value:
            return 0.0
        words = len(value.split())
        return 1.0 if words >= (4 if key in {"objective", "instructions"} else 2) else 0.6

    @staticmethod
    def _feedback(label: str, status: str) -> str:
        if status == "good":
            return f"{label} está claro e útil para orientar a resposta."
        if status == "partial":
            return f"{label} está presente, mas pode ser mais específico."
        return f"{label} não foi identificado no prompt."

    @staticmethod
    def _suggestion(key: str) -> str:
        return {
            "objective": "Descreva o resultado exato que deseja obter.",
            "context": "Inclua onde e em qual situação o resultado será usado.",
            "audience": "Defina para quem a resposta será criada.",
            "instructions": "Adicione passos ou orientações objetivas.",
            "clarity": "Use frases diretas e elimine ambiguidades.",
            "output_format": "Informe o formato esperado da resposta.",
            "constraints": "Inclua limites e condições importantes.",
            "tone": "Escolha o tom adequado ao objetivo.",
            "language": "Informe o idioma da resposta.",
            "specificity": "Acrescente detalhes próprios da tarefa e da categoria.",
        }[key]

    @staticmethod
    def _rating(score: int) -> str:
        if score >= 90:
            return "excellent"
        if score >= 75:
            return "very_good"
        if score >= 60:
            return "good"
        if score >= 40:
            return "needs_improvement"
        return "weak"
