import re
import unicodedata
from dataclasses import dataclass

from app.modules.prompt_engine.schemas import PromptGenerateRequest


@dataclass(frozen=True)
class ResolvedContext:
    values: dict[str, str]


class ContextEngine:
    """Resolve only user-provided or deterministically detected context."""

    LABELS = {
        "product": "Produto",
        "product_details": "Detalhes do produto",
        "platform": "Plataforma",
        "duration": "Duração",
        "content_type": "Tipo de conteúdo",
        "channel": "Canal",
        "cta": "Chamada para ação",
        "offer_details": "Detalhes da oferta",
        "sales_stage": "Etapa da venda",
        "objections": "Objeções",
        "content_formats": "Formatos de conteúdo",
        "commercial_conditions": "Condições comerciais",
        "stack": "Stack",
        "requirements": "Requisitos",
        "business_context": "Contexto do negócio",
        "desired_outcome": "Resultado desejado",
        "stakeholders": "Partes interessadas",
        "subject": "Assunto",
        "learning_level": "Nível de aprendizagem",
        "learning_outcome": "Objetivo de aprendizagem",
        "text_type": "Tipo de texto",
        "central_message": "Mensagem central",
        "references": "Referências",
        "visual_subject": "Assunto visual",
        "visual_style": "Estilo visual",
        "dimensions": "Dimensões",
        "video_style": "Estilo do vídeo",
        "current_workflow": "Fluxo atual",
        "available_tools": "Ferramentas disponíveis",
    }
    PLATFORMS = {
        "instagram": "Instagram",
        "facebook": "Facebook",
        "tiktok": "TikTok",
        "youtube": "YouTube",
        "linkedin": "LinkedIn",
        "whatsapp": "WhatsApp",
        "google": "Google",
    }
    CONTENT_TYPES = (
        "anúncio", "campanha", "post", "carrossel", "story", "vídeo",
        "imagem", "contrato", "artigo", "api", "site", "aplicativo",
    )
    NUMBER_WORDS = {
        "dez": "10", "quinze": "15", "vinte": "20", "trinta": "30",
        "quarenta": "40", "cinquenta": "50", "sessenta": "60",
    }

    def resolve(self, data: PromptGenerateRequest) -> ResolvedContext:
        inferred = self._infer(data.input)
        values = dict(inferred)
        for key, value in data.smart_answers.items():
            if key not in {"audience", "tone", "language", "context"}:
                values[key] = self._normalize_value(key, value)
        return ResolvedContext(values=self._deduplicate(values))

    def render(self, data: PromptGenerateRequest) -> str | None:
        resolved = self.resolve(data).values
        lines: list[str] = []
        for key, value in resolved.items():
            label = self.LABELS.get(key)
            if label is None:
                continue
            quoted = "\n".join(f"> {line}" if line else ">" for line in value.splitlines())
            lines.append(f"- {label}:\n{quoted}")
        return "\n".join(lines) or None

    def _infer(self, value: str) -> dict[str, str]:
        normalized = self._fold(value)
        result: dict[str, str] = {}
        for token, display in self.PLATFORMS.items():
            if self._contains(normalized, token):
                result["platform"] = display
                break
        duration = re.search(r"\b(\d{1,3})\s*(s|segundos?|minutos?)\b", normalized)
        if duration:
            unit = "segundos" if duration.group(2) in {"s", "segundo", "segundos"} else "minutos"
            result["duration"] = f"{duration.group(1)} {unit}"
        else:
            words = "|".join(self.NUMBER_WORDS)
            word_duration = re.search(rf"\b({words})\s+(segundos?|minutos?)\b", normalized)
            if word_duration:
                unit = "segundos" if word_duration.group(2).startswith("segundo") else "minutos"
                result["duration"] = f"{self.NUMBER_WORDS[word_duration.group(1)]} {unit}"
        for content_type in self.CONTENT_TYPES:
            if self._contains(normalized, self._fold(content_type)):
                result["content_type"] = content_type.upper() if content_type == "api" else content_type
                break
        product = re.search(
            r"\b(?:vender|divulgar|anunciar)\s+(?:um|uma|o|a)?\s*([^,.]+?)"
            r"(?=\s+(?:no|na|pelo|pela|para)\b|[,.]|$)",
            value,
            re.IGNORECASE,
        )
        if product and 2 <= len(product.group(1).strip()) <= 120:
            result["product"] = product.group(1).strip().rstrip(".")
        return result

    def _normalize_value(self, key: str, value: str) -> str:
        clean = "\n".join(line.strip() for line in value.splitlines()).strip()
        compact = " ".join(clean.split())
        if key == "platform":
            return self.PLATFORMS.get(self._fold(compact), compact)
        if key == "duration":
            inferred = self._infer(f"vídeo de {compact}").get("duration")
            return inferred or compact
        if key == "stack":
            names = {"python": "Python", "fastapi": "FastAPI", "javascript": "JavaScript"}
            return names.get(self._fold(compact), compact)
        return clean

    def _deduplicate(self, values: dict[str, str]) -> dict[str, str]:
        result: dict[str, str] = {}
        seen: set[str] = set()
        for key, value in values.items():
            signature = self._fold(value).rstrip(".")
            if not signature or signature in seen:
                continue
            seen.add(signature)
            result[key] = value
        return result

    @staticmethod
    def _fold(value: str) -> str:
        decomposed = unicodedata.normalize("NFKD", value.casefold())
        return " ".join(
            "".join(char for char in decomposed if not unicodedata.combining(char)).split()
        )

    @staticmethod
    def _contains(value: str, term: str) -> bool:
        return re.search(rf"(?<!\w){re.escape(term)}(?!\w)", value) is not None
