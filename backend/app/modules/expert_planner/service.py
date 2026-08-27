import re
import unicodedata

from app.modules.context_engine import ContextEngine
from app.modules.projects.service import ProjectService
from app.modules.prompt_chains.schemas import ChainDetail
from app.modules.prompt_chains.service import PromptChainService
from app.modules.prompt_engine.enums import PromptCategory, PromptMode, TargetAI
from app.modules.prompt_engine.schemas import PromptGenerateRequest
from app.modules.users.model import User

from .schemas import CreateChainFromPlan, ExpertPlan, ExpertPlanRequest, ExpertPlanStep


class ExpertPlannerService:
    COMPLEX_TERMS = (
        "aplicativo", "marketplace", "plataforma", "sistema", "e-commerce", "ecommerce",
        "curso", "lancamento", "pesquisa", "plano de negocio", "website", "site",
    )
    COMPONENT_TERMS = (
        "usuarios", "autenticacao", "pagamentos", "painel", "aplicativo", "backend",
        "frontend", "api", "banco de dados", "pedidos", "catalogo", "cardapio",
    )

    def __init__(self, session) -> None:
        self.session = session

    async def plan(self, user: User, data: ExpertPlanRequest) -> ExpertPlan:
        if data.project_id is not None:
            await ProjectService(self.session).accessible(data.project_id, user)
        prompt_data = PromptGenerateRequest(
            input=data.input,
            project_id=data.project_id,
            category=data.category,
            mode=data.mode,
            target_ai=data.target_ai,
            smart_answers=data.smart_answers,
        )
        context = ContextEngine().resolve(prompt_data).values
        plan_type = self._plan_type(data.input, data.category)
        recommended = self._recommended(data.input, plan_type)
        steps = self._steps(plan_type, data, context)
        return ExpertPlan(
            summary=data.input.rstrip(" ."),
            suggested_name=self._name(data.input, plan_type),
            planning_recommended=recommended,
            plan_type=plan_type,
            steps=[
                ExpertPlanStep(position=index, **step)
                for index, step in enumerate(steps, 1)
            ],
        )

    async def create_chain(self, user: User, data: CreateChainFromPlan) -> ChainDetail:
        if data.project_id is not None:
            await ProjectService(self.session).accessible(data.project_id, user)
        chains = PromptChainService(self.session)
        for step in data.steps:
            await chains._template(step.template_id, user)
        chain = await chains.repository.create_with_steps(
            chain_values={
                "user_id": user.id,
                "name": data.name,
                "description": data.description,
                "project_id": data.project_id,
            },
            steps=[step.model_dump() for step in data.steps],
        )
        return await chains.detail(chain.id, user)

    def _recommended(self, value: str, plan_type: str) -> bool:
        folded = self._fold(value)
        complex_count = sum(term in folded for term in self.COMPLEX_TERMS)
        component_count = sum(term in folded for term in self.COMPONENT_TERMS)
        connectors = len(re.findall(r"\b(?:com|e|incluindo|além de)\b", folded))
        return plan_type != "general" and (component_count >= 2 or complex_count + connectors >= 3)

    def _plan_type(self, value: str, category: PromptCategory) -> str:
        folded = self._fold(value)
        rules = (
            ("software", ("aplicativo", "software", "sistema", "api", "marketplace")),
            ("website", ("website", "site", "portal")),
            ("ecommerce", ("e-commerce", "ecommerce", "loja virtual")),
            ("research", ("pesquisa", "pesquisar", "estudo de mercado")),
            ("education", ("curso", "aula", "treinamento", "educacao")),
            ("video", ("video", "audiovisual", "filme")),
            ("business", ("plano de negocio", "negocio", "empresa")),
            ("launch", ("lancar", "lancamento", "nova marca", "novo produto")),
            ("marketing", ("campanha", "marketing", "anuncio")),
            ("content", ("conteudo", "artigo", "newsletter", "podcast")),
        )
        for plan_type, terms in rules:
            if any(term in folded for term in terms):
                return plan_type
        category_map = {
            PromptCategory.PROGRAMMING: "software",
            PromptCategory.MARKETING: "marketing",
            PromptCategory.SALES: "marketing",
            PromptCategory.ECOMMERCE: "ecommerce",
            PromptCategory.EDUCATION: "education",
            PromptCategory.VIDEO: "video",
            PromptCategory.WRITING: "content",
            PromptCategory.BUSINESS: "business",
        }
        return category_map.get(category, "general")

    def _steps(
        self, plan_type: str, data: ExpertPlanRequest, context: dict[str, str]
    ) -> list[dict[str, object]]:
        definitions = self._definitions(plan_type)
        folded = self._fold(data.input)
        if plan_type == "software":
            if "pagamento" not in folded:
                definitions = [item for item in definitions if item[0] != "Planejar pagamentos"]
            if not any(term in folded for term in ("usuario", "autenticacao", "login")):
                definitions = [item for item in definitions if item[0] != "Planejar autenticação"]
        detail = context.get("stack") or context.get("platform")
        target = self._target(plan_type)
        result: list[dict[str, object]] = []
        for index, (title, objective, depends) in enumerate(definitions):
            suffix = f" Considere o contexto informado: {detail}." if detail and index > 0 else ""
            base = f"{objective} para o projeto descrito pelo usuário.{suffix}"
            if depends:
                base = f"{base} Use como contexto o resultado anterior: {{resultado_anterior}}"
            result.append({
                "title": title,
                "objective": objective,
                "base_input": base,
                "category": self._category(plan_type),
                "mode": PromptMode.EXPERT,
                "target_ai": target,
                "requires_previous_result": depends,
            })
        return result[:10]

    @staticmethod
    def _definitions(plan_type: str) -> list[tuple[str, str, bool]]:
        plans = {
            "software": [
                ("Definir requisitos e escopo", "Defina requisitos, atores e limites do produto", False),
                ("Projetar arquitetura", "Projete a arquitetura coerente com os requisitos", True),
                ("Modelar dados", "Modele os dados e relacionamentos necessários", True),
                ("Definir API e backend", "Defina serviços, APIs e regras do backend", True),
                ("Planejar autenticação", "Planeje autenticação e autorização", True),
                ("Planejar frontend", "Planeje a experiência e implementação do frontend", True),
                ("Planejar pagamentos", "Planeje a integração de pagamentos informada", True),
                ("Definir testes", "Defina testes e critérios de qualidade", True),
                ("Preparar publicação", "Prepare deploy, publicação e operação", True),
            ],
            "marketing": [
                ("Definir objetivo", "Defina o objetivo mensurável da iniciativa", False),
                ("Definir público e proposta", "Organize público e proposta de valor", True),
                ("Planejar campanha", "Crie a estratégia e os canais da campanha", True),
                ("Criar conteúdo", "Planeje as peças e mensagens necessárias", True),
                ("Definir métricas", "Defina métricas e critérios de avaliação", True),
            ],
            "launch": [
                ("Definir posicionamento", "Defina posicionamento e proposta de valor", False),
                ("Definir público", "Defina o público usando somente dados disponíveis", True),
                ("Criar estratégia de lançamento", "Planeje fases e canais do lançamento", True),
                ("Planejar campanha", "Planeje campanha e conteúdo", True),
                ("Definir métricas", "Defina métricas para acompanhar o lançamento", True),
            ],
            "research": [
                ("Definir escopo", "Delimite o tema e o escopo da pesquisa", False),
                ("Definir perguntas", "Formule perguntas de pesquisa", True),
                ("Identificar fontes", "Defina critérios e fontes de evidência", True),
                ("Planejar coleta", "Planeje a coleta dos dados", True),
                ("Analisar resultados", "Defina a análise das evidências", True),
                ("Criar relatório", "Estruture o relatório final", True),
            ],
            "education": [
                ("Definir objetivos de aprendizagem", "Defina resultados de aprendizagem", False),
                ("Estruturar conteúdo", "Organize módulos e progressão", True),
                ("Criar atividades", "Planeje atividades e exemplos", True),
                ("Definir avaliação", "Defina critérios e instrumentos de avaliação", True),
            ],
            "video": [
                ("Definir conceito", "Defina conceito, objetivo e público", False),
                ("Criar roteiro", "Estruture o roteiro e a narrativa", True),
                ("Planejar produção", "Planeje cenas, recursos e captação", True),
                ("Planejar pós-produção", "Defina edição, áudio e entrega", True),
            ],
            "ecommerce": [
                ("Definir catálogo e operação", "Defina catálogo, pedidos e operação", False),
                ("Planejar experiência de compra", "Planeje navegação e conversão", True),
                ("Planejar tecnologia", "Defina integrações e requisitos técnicos", True),
                ("Planejar lançamento", "Planeje publicação e aquisição", True),
            ],
            "website": [
                ("Definir escopo", "Defina objetivos e requisitos do website", False),
                ("Planejar arquitetura de informação", "Organize páginas e navegação", True),
                ("Planejar interface", "Defina experiência e componentes", True),
                ("Planejar implementação", "Defina construção, testes e publicação", True),
            ],
            "business": [
                ("Definir proposta", "Defina problema, público e proposta de valor", False),
                ("Analisar mercado", "Planeje a análise de mercado", True),
                ("Definir operação", "Estruture operação e recursos", True),
                ("Definir modelo financeiro", "Planeje premissas financeiras sem inventar valores", True),
                ("Criar plano", "Consolide o plano de negócio", True),
            ],
            "content": [
                ("Definir objetivo editorial", "Defina objetivo, público e mensagem", False),
                ("Estruturar conteúdo", "Organize tópicos e sequência", True),
                ("Produzir versão", "Crie o conteúdo conforme a estrutura", True),
                ("Revisar e publicar", "Planeje revisão e publicação", True),
            ],
            "general": [
                ("Definir objetivo e escopo", "Defina o objetivo e os limites do projeto", False),
                ("Planejar execução", "Organize atividades e dependências", True),
                ("Definir validação", "Defina critérios para validar o resultado", True),
            ],
        }
        return plans[plan_type]

    @staticmethod
    def _category(plan_type: str) -> PromptCategory:
        return {
            "software": PromptCategory.PROGRAMMING,
            "website": PromptCategory.PROGRAMMING,
            "marketing": PromptCategory.MARKETING,
            "launch": PromptCategory.MARKETING,
            "ecommerce": PromptCategory.ECOMMERCE,
            "research": PromptCategory.BUSINESS,
            "business": PromptCategory.BUSINESS,
            "education": PromptCategory.EDUCATION,
            "content": PromptCategory.WRITING,
            "video": PromptCategory.VIDEO,
        }.get(plan_type, PromptCategory.GENERAL)

    @staticmethod
    def _target(plan_type: str) -> TargetAI:
        return {
            "software": TargetAI.CODING_ASSISTANT,
            "website": TargetAI.CODING_ASSISTANT,
            "video": TargetAI.VIDEO_GENERATOR,
        }.get(plan_type, TargetAI.GENERIC)

    def _name(self, value: str, plan_type: str) -> str:
        compact = re.sub(r"(?i)^\s*(?:quero|preciso|desejo)\s+(?:criar|lançar|pesquisar)?\s*", "", value)
        compact = compact.strip(" .")
        compact = re.split(r"\s+com\s+|[,.]", compact, maxsplit=1, flags=re.IGNORECASE)[0]
        return (compact[:197].strip() or f"Plano de {plan_type}").capitalize()

    @staticmethod
    def _fold(value: str) -> str:
        decomposed = unicodedata.normalize("NFKD", value.casefold())
        return " ".join(
            "".join(char for char in decomposed if not unicodedata.combining(char)).split()
        )
