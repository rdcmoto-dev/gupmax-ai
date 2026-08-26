import re
import unicodedata
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from app.modules.prompt_engine.enums import PromptCategory
from app.modules.prompt_engine.schemas import PromptGenerateRequest


class FactSource(StrEnum):
    PROFILE = "profile"
    PROJECT = "project"
    INITIAL_REQUEST = "initial_request"
    FORM = "form"
    ANSWER = "answer"
    AI_EXTRACTION = "ai_extraction"


class InterviewFact(BaseModel):
    model_config = ConfigDict(frozen=True)

    value: str | bool | list[str] | dict[str, str]
    source: FactSource
    confidence: float = Field(ge=0, le=1)
    detail: str | None = None


PLATFORMS = {
    "instagram": "Instagram",
    "facebook": "Facebook",
    "tiktok": "TikTok",
    "youtube": "YouTube",
    "google": "Google",
    "whatsapp": "WhatsApp",
}
TONES = (
    "profissional",
    "persuasivo",
    "casual",
    "tecnico",
    "inspirador",
    "elegante",
    "divertido",
    "formal",
)
STACKS = (
    "react native",
    "next.js",
    "javascript",
    "typescript",
    "fastapi",
    "flutter",
    "python",
    "react",
    "vue",
    "angular",
    "django",
    "node.js",
)


class DeterministicFactExtractor:
    def extract(self, initial_request: str, category: PromptCategory) -> dict[str, InterviewFact]:
        normalized = self._normalize(initial_request)
        facts: dict[str, InterviewFact] = {}
        platform = next((label for token, label in PLATFORMS.items() if self._contains(normalized, token)), None)

        if platform:
            if category in {PromptCategory.SOCIAL_MEDIA, PromptCategory.VIDEO}:
                facts["platform"] = self._fact(platform, detail=platform)
            elif category == PromptCategory.MARKETING:
                channel = (
                    "rede social"
                    if platform not in {"Google", "WhatsApp"}
                    else ("busca" if platform == "Google" else "outro")
                )
                facts["channel"] = self._fact(channel, detail=platform)
        elif self._contains(normalized, "site"):
            key = "platform" if category in {PromptCategory.VIDEO, PromptCategory.PROGRAMMING} else "channel"
            facts[key] = self._fact("site", detail="site")
        elif self._contains(normalized, "e-mail") or self._contains(normalized, "email"):
            facts["channel"] = self._fact("e-mail", detail="e-mail")

        if category == PromptCategory.PROGRAMMING and self._contains(normalized, "site"):
            facts["platform"] = self._fact("site", detail="site")

        tone = next(
            (
                tone
                for tone in TONES
                if re.search(rf"\btom\s+(?:de\s+)?{re.escape(tone)}\b", normalized)
                or re.search(rf"\b(?:anuncio|texto|comunicacao)\s+{re.escape(tone)}\b", normalized)
            ),
            None,
        )
        if tone:
            facts["tone"] = self._fact(self._display_tone(tone))

        audience = self._audience(initial_request)
        if audience:
            facts["audience"] = self._fact(audience)

        if category in {PromptCategory.MARKETING, PromptCategory.ECOMMERCE, PromptCategory.SOCIAL_MEDIA}:
            cta = re.search(
                r"\b(?:cta|chamada\s+para\s+acao)\s*[:=-]?\s*[\"']?([^,.\"']+)",
                normalized,
            )
            if cta and len(cta.group(1).strip()) >= 3:
                facts["cta"] = self._fact(cta.group(1).strip())

        language = self._language(normalized)
        if language:
            facts["language"] = self._fact(language)

        if category == PromptCategory.VIDEO:
            duration = re.search(r"\b(\d{1,3}\s*(?:segundos?|minutos?|h(?:oras?)?))\b", normalized)
            if duration:
                facts["duration"] = self._fact(duration.group(1))

        if category == PromptCategory.PROGRAMMING:
            stack = next((item for item in STACKS if self._contains(normalized, item)), None)
            if stack:
                facts["stack"] = self._fact(self._display_stack(stack))

        return facts

    @staticmethod
    def from_form(data: PromptGenerateRequest) -> dict[str, InterviewFact]:
        fields: dict[str, Any] = {
            "language": data.language,
            "tone": data.tone,
            "title": data.title,
            "context": data.context,
            "audience": data.audience,
            "role": data.role,
            "instructions": data.instructions,
            "constraints": data.constraints,
            "output_format": data.output_format,
            "additional_information": data.additional_information,
            "provider": data.provider,
            "model": data.model,
            "project_id": str(data.project_id) if data.project_id is not None else None,
            "chain_id": str(data.chain_id) if data.chain_id is not None else None,
            "chain_step_id": str(data.chain_step_id) if data.chain_step_id is not None else None,
            "previous_result": data.previous_result,
            "target_ai": data.target_ai.value,
            "comparison_target_ais": [target.value for target in data.comparison_target_ais],
            "template_id": str(data.template_id) if data.template_id is not None else None,
            "variable_values": data.variable_values,
            "optimize_with_ai": data.optimize_with_ai,
        }
        for key, value in data.smart_answers.items():
            if not fields.get(key):
                fields[key] = value
        return {
            key: InterviewFact(value=value, source=FactSource.FORM, confidence=1.0)
            for key, value in fields.items()
            if value is not None and value != [] and (key != "optimize_with_ai" or value is True)
        }

    @staticmethod
    def from_profile(profile: Any) -> dict[str, InterviewFact]:
        fields: dict[str, Any] = {
            "language": profile.default_language,
            "tone": profile.default_tone,
            "audience": profile.default_audience,
            "channel": profile.default_channel,
            "context": profile.business_context,
            "output_format": profile.default_output_format,
            "constraints": profile.default_constraints,
            "instructions": profile.default_instructions,
        }
        return {
            key: InterviewFact(value=value, source=FactSource.PROFILE, confidence=1.0)
            for key, value in fields.items()
            if value is not None and value != []
        }

    @staticmethod
    def dump(facts: dict[str, InterviewFact]) -> dict[str, dict[str, Any]]:
        return {key: fact.model_dump(mode="json") for key, fact in facts.items()}

    @staticmethod
    def load(raw: dict[str, Any]) -> dict[str, InterviewFact]:
        return {key: InterviewFact.model_validate(value) for key, value in raw.items()}

    @staticmethod
    def _fact(value: str, *, detail: str | None = None) -> InterviewFact:
        return InterviewFact(value=value, source=FactSource.INITIAL_REQUEST, confidence=1.0, detail=detail)

    @staticmethod
    def _normalize(value: str) -> str:
        decomposed = unicodedata.normalize("NFKD", value.casefold())
        return "".join(character for character in decomposed if not unicodedata.combining(character))

    @staticmethod
    def _contains(text: str, value: str) -> bool:
        return re.search(rf"(?<!\w){re.escape(value)}(?!\w)", text) is not None

    def _audience(self, original: str) -> str | None:
        patterns = (
            r"\bpara\s+((?:mulheres|homens|jovens|adultos|criancas|crianças|adolescentes|idosos|estudantes|profissionais|empreendedores)\b[^,.]*)",
            r"\bpublico\s+(?:de\s+)?((?:mulheres|homens|jovens|adultos|criancas|crianças|adolescentes|idosos|estudantes|profissionais|empreendedores)\b[^,.]*)",
            r"\bpúblico\s+(?:de\s+)?((?:mulheres|homens|jovens|adultos|crianças|adolescentes|idosos|estudantes|profissionais|empreendedores)\b[^,.]*)",
        )
        normalized = self._normalize(original)
        matches: list[str] = []
        for pattern in patterns:
            matches.extend(match.group(1).strip() for match in re.finditer(pattern, normalized, re.IGNORECASE))
        if not matches:
            return None
        value = matches[-1]
        value = re.split(r"\s+com\s+tom\b", value, maxsplit=1)[0].strip()
        return value if len(value) >= 6 else None

    @staticmethod
    def _language(normalized: str) -> str | None:
        for pattern, value in (
            (r"\b(?:em|idioma)\s+ingles\b", "en-US"),
            (r"\b(?:em|idioma)\s+espanhol\b", "es"),
            (r"\b(?:em|idioma)\s+portugues\b", "pt-BR"),
        ):
            if re.search(pattern, normalized):
                return value
        return None

    @staticmethod
    def _display_tone(value: str) -> str:
        return "técnico" if value == "tecnico" else value

    @staticmethod
    def _display_stack(value: str) -> str:
        names = {"react": "React", "react native": "React Native", "next.js": "Next.js", "fastapi": "FastAPI"}
        return names.get(value, value)
