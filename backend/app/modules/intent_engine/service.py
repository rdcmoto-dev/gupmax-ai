import re
import unicodedata

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.interviews.facts import PLATFORMS, STACKS, DeterministicFactExtractor
from app.modules.interviews.question_generator import CATEGORY_QUESTIONS, COMMON_QUESTIONS
from app.modules.projects.service import ProjectService
from app.modules.prompt_engine.enums import PromptCategory
from app.modules.prompt_templates.repository import PromptTemplateRepository
from app.modules.users.model import User

from .schemas import IntentAnalysis, IntentAnalyzeRequest, IntentQuestion


class IntentEngineService:
    MAX_QUESTIONS = 5

    _RULES: tuple[tuple[PromptCategory, str, tuple[str, ...]], ...] = (
        (PromptCategory.VIDEO, "video_creation", ("video", "roteiro de video", "filme", "reel")),
        (PromptCategory.IMAGE, "image_creation", ("imagem", "foto", "ilustracao", "logo", "banner")),
        (
            PromptCategory.PROGRAMMING,
            "software_development",
            ("api", "codigo", "programa", "aplicativo", "software", "site", *STACKS),
        ),
        (
            PromptCategory.EDUCATION,
            "education",
            ("explique", "ensine", "aula", "atividade escolar", "estudante", "crianca"),
        ),
        (
            PromptCategory.ECOMMERCE,
            "ecommerce",
            ("e-commerce", "ecommerce", "loja virtual", "pagina de produto", "catalogo"),
        ),
        (
            PromptCategory.SOCIAL_MEDIA,
            "social_media_content",
            ("post", "carrossel", "story", "stories", "rede social", "tiktok", "linkedin"),
        ),
        (PromptCategory.SALES, "sales", ("vender", "venda", "proposta comercial", "oferta")),
        (
            PromptCategory.MARKETING,
            "marketing_campaign",
            ("anuncio", "campanha", "marketing", "divulgar", "publicidade"),
        ),
        (
            PromptCategory.BUSINESS,
            "business",
            ("negocio", "plano de negocios", "estrategia empresarial", "contrato comercial"),
        ),
        (
            PromptCategory.WRITING,
            "writing",
            ("escreva", "texto", "artigo", "email", "contrato", "historia", "resumo"),
        ),
        (
            PromptCategory.PRODUCTIVITY,
            "productivity",
            ("organizar", "planejar", "produtividade", "cronograma", "tarefas", "processo"),
        ),
    )

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def analyze(self, user: User, data: IntentAnalyzeRequest) -> IntentAnalysis:
        await self._validate_context_ownership(user, data)
        normalized = self._normalize(data.input)
        category, intent, matched = self._detect_category(normalized)
        entities = self._entities(data.input, normalized, category)
        questions = self._questions(category, set(entities))
        confidence = min(0.98, (0.78 if matched else 0.45) + min(len(entities), 4) * 0.04)
        return IntentAnalysis(
            summary=data.input.rstrip(" ."),
            intent=intent,
            suggested_category=category,
            detected_entities=entities,
            missing_information=[question.key for question in questions],
            suggested_questions=questions,
            confidence=round(confidence, 2),
        )

    async def _validate_context_ownership(self, user: User, data: IntentAnalyzeRequest) -> None:
        if data.project_id is not None:
            await ProjectService(self.session).accessible(data.project_id, user)
        if data.template_id is not None:
            template = await PromptTemplateRepository(self.session).get(data.template_id)
            if template is None or template.user_id != user.id:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Template not found")

    def _detect_category(self, normalized: str) -> tuple[PromptCategory, str, bool]:
        for category, intent, terms in self._RULES:
            if any(self._contains(normalized, term) for term in terms):
                return category, intent, True
        return PromptCategory.GENERAL, "general_request", False

    def _entities(
        self, original: str, normalized: str, category: PromptCategory
    ) -> dict[str, str]:
        entities: dict[str, str] = {}
        platform = next(
            (label for token, label in PLATFORMS.items() if self._contains(normalized, token)), None
        )
        if platform:
            entities["platform"] = platform
        duration = re.search(r"\b(\d{1,3}\s*(?:segundos?|minutos?|horas?))\b", normalized)
        if duration:
            entities["duration"] = duration.group(1)
        stacks = [item for item in STACKS if self._contains(normalized, item)]
        languages = [item for item in stacks if item in {"python", "javascript", "typescript", "dart"}]
        frameworks = [item for item in stacks if item not in languages]
        if languages:
            entities["programming_language"] = self._display(languages[0])
        if frameworks:
            entities["framework"] = self._display(frameworks[0])
        facts = DeterministicFactExtractor().extract(original, category)
        for key in ("audience", "language", "tone"):
            if key in facts:
                entities[key] = str(facts[key].value)
        content_types = (
            "anúncio", "campanha", "post", "carrossel", "story", "vídeo", "imagem",
            "contrato", "artigo", "api", "site", "aplicativo",
        )
        content_type = next(
            (item for item in content_types if self._contains(normalized, self._normalize(item))), None
        )
        if content_type:
            entities["content_type"] = content_type
        product = re.search(
            r"\b(?:vender|divulgar|anunciar)\s+(?:um|uma|o|a)?\s*([^,.]+?)(?=\s+(?:no|na|pelo|pela|para)\b|[,.]|$)",
            original,
            re.IGNORECASE,
        )
        if product and 2 <= len(product.group(1).strip()) <= 120:
            entities["product"] = product.group(1).strip()
        return entities

    def _questions(self, category: PromptCategory, known: set[str]) -> list[IntentQuestion]:
        aliases = {
            "programming_language": "stack",
            "framework": "stack",
            "product": "product_details",
            "content_type": "text_type",
        }
        known_keys = known | {aliases[key] for key in known if key in aliases}
        candidates = [*CATEGORY_QUESTIONS[category], *COMMON_QUESTIONS[:2]]
        result: list[IntentQuestion] = []
        seen: set[str] = set()
        for question in candidates:
            if question.key in known_keys or question.key in seen:
                continue
            seen.add(question.key)
            result.append(IntentQuestion(key=question.key, label=question.text))
            if len(result) == self.MAX_QUESTIONS:
                break
        return result

    @staticmethod
    def _normalize(value: str) -> str:
        value = unicodedata.normalize("NFKD", value.casefold())
        return " ".join("".join(char for char in value if not unicodedata.combining(char)).split())

    @staticmethod
    def _contains(value: str, term: str) -> bool:
        return re.search(rf"(?<!\w){re.escape(term)}(?!\w)", value) is not None

    @staticmethod
    def _display(value: str) -> str:
        names = {"fastapi": "FastAPI", "javascript": "JavaScript", "typescript": "TypeScript"}
        return names.get(value, value.capitalize())
