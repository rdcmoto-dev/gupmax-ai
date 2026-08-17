from app.modules.interviews.enums import QuestionType
from app.modules.interviews.schemas import InterviewQuestion
from app.modules.prompt_engine.enums import PromptCategory, PromptMode


def _question(
    key: str,
    text: str,
    question_type: QuestionType = QuestionType.TEXT,
    *,
    required: bool = True,
    options: tuple[str, ...] = (),
) -> InterviewQuestion:
    return InterviewQuestion(key=key, text=text, type=question_type, required=required, options=list(options))


COMMON_QUESTIONS = (
    _question("audience", "Para qual público a resposta deve ser direcionada?", QuestionType.MULTILINE),
    _question(
        "tone",
        "Qual tom deve ser usado?",
        QuestionType.SINGLE_CHOICE,
        options=("profissional", "persuasivo", "casual", "técnico", "inspirador"),
    ),
    _question(
        "language",
        "Em qual idioma a resposta deve ser produzida?",
        QuestionType.SINGLE_CHOICE,
        options=("pt-BR", "en-US", "es"),
    ),
)

EXPERT_QUESTIONS = (
    _question("success_criteria", "Quais critérios definem uma resposta bem-sucedida?", QuestionType.MULTILINE),
    _question("constraints", "Quais restrições devem ser respeitadas?", QuestionType.MULTILINE, required=False),
    _question("output_format", "Qual formato de entrega você espera?"),
    _question(
        "include_examples",
        "A resposta deve incluir exemplos?",
        QuestionType.BOOLEAN,
        required=False,
    ),
)

CATEGORY_QUESTIONS: dict[PromptCategory, tuple[InterviewQuestion, ...]] = {
    PromptCategory.MARKETING: (
        _question(
            "channel",
            "Em qual canal ou plataforma o conteúdo será usado?",
            QuestionType.SINGLE_CHOICE,
            options=("site", "e-mail", "busca", "rede social", "mídia offline", "outro"),
        ),
        _question("cta", "Qual ação você quer que o público realize?"),
        _question("offer_details", "Quais diferenciais da oferta precisam aparecer?", QuestionType.MULTILINE),
    ),
    PromptCategory.SALES: (
        _question(
            "offer_details", "O que está sendo vendido e quais são os principais diferenciais?", QuestionType.MULTILINE
        ),
        _question(
            "sales_stage",
            "Em qual etapa da venda o material será usado?",
            QuestionType.SINGLE_CHOICE,
            options=("prospecção", "qualificação", "proposta", "negociação", "fechamento"),
        ),
        _question("objections", "Quais objeções devem ser tratadas?", QuestionType.MULTILINE, required=False),
    ),
    PromptCategory.SOCIAL_MEDIA: (
        _question(
            "platform",
            "Para qual rede social o conteúdo será criado?",
            QuestionType.SINGLE_CHOICE,
            options=("Instagram", "TikTok", "LinkedIn", "YouTube", "Facebook", "outra"),
        ),
        _question(
            "content_formats",
            "Quais formatos devem ser considerados?",
            QuestionType.MULTI_CHOICE,
            options=("post", "carrossel", "story", "reel", "vídeo", "live"),
        ),
        _question("cta", "Qual interação ou ação o conteúdo deve estimular?"),
    ),
    PromptCategory.ECOMMERCE: (
        _question(
            "product_details", "Quais características e benefícios do produto devem aparecer?", QuestionType.MULTILINE
        ),
        _question(
            "commercial_conditions", "Quais preços, condições ou promoções devem ser considerados?", required=False
        ),
        _question("cta", "Qual deve ser a chamada para ação?"),
    ),
    PromptCategory.PROGRAMMING: (
        _question("stack", "Qual linguagem, framework ou stack deve ser utilizada?"),
        _question(
            "platform",
            "Qual é a plataforma de destino?",
            QuestionType.SINGLE_CHOICE,
            options=("web", "mobile", "backend", "desktop", "infraestrutura", "outra"),
        ),
        _question("requirements", "Quais funcionalidades e requisitos precisam ser atendidos?", QuestionType.MULTILINE),
    ),
    PromptCategory.BUSINESS: (
        _question("business_context", "Qual é o contexto do negócio e o problema a resolver?", QuestionType.MULTILINE),
        _question("desired_outcome", "Qual resultado de negócio você espera obter?"),
        _question("stakeholders", "Quem são as partes interessadas?", QuestionType.MULTILINE, required=False),
    ),
    PromptCategory.EDUCATION: (
        _question("subject", "Qual assunto ou habilidade deve ser ensinada?"),
        _question(
            "learning_level",
            "Qual é o nível atual dos estudantes?",
            QuestionType.SINGLE_CHOICE,
            options=("iniciante", "intermediário", "avançado", "misto"),
        ),
        _question("learning_outcome", "O que o estudante deve conseguir fazer ao final?", QuestionType.MULTILINE),
    ),
    PromptCategory.WRITING: (
        _question("text_type", "Qual tipo de texto deve ser produzido?"),
        _question(
            "central_message", "Qual mensagem ou argumento central deve ser desenvolvido?", QuestionType.MULTILINE
        ),
        _question("references", "Existem referências ou fontes obrigatórias?", QuestionType.MULTILINE, required=False),
    ),
    PromptCategory.IMAGE: (
        _question("visual_subject", "Qual deve ser o assunto principal da imagem?", QuestionType.MULTILINE),
        _question("visual_style", "Qual estilo visual deve ser seguido?"),
        _question("dimensions", "Qual proporção ou dimensão é necessária?", required=False),
    ),
    PromptCategory.VIDEO: (
        _question(
            "platform",
            "Em qual plataforma o vídeo será publicado?",
            QuestionType.SINGLE_CHOICE,
            options=("YouTube", "Instagram", "TikTok", "site", "apresentação", "outra"),
        ),
        _question("duration", "Qual deve ser a duração aproximada?"),
        _question("video_style", "Qual estilo ou ritmo o vídeo deve ter?"),
    ),
    PromptCategory.PRODUCTIVITY: (
        _question("current_workflow", "Como o processo funciona atualmente?", QuestionType.MULTILINE),
        _question("desired_outcome", "Qual melhoria ou resultado você quer alcançar?"),
        _question("available_tools", "Quais ferramentas podem ser utilizadas?", QuestionType.MULTILINE, required=False),
    ),
    PromptCategory.GENERAL: (
        _question("context", "Que contexto adicional é importante para executar a tarefa?", QuestionType.MULTILINE),
        _question("desired_outcome", "Como deve ser o resultado ideal?", QuestionType.MULTILINE),
        _question("references", "Há exemplos ou referências a considerar?", QuestionType.MULTILINE, required=False),
    ),
}


class DeterministicQuestionGenerator:
    MAX_EXPERT_QUESTIONS = 10

    def generate(
        self, mode: PromptMode, category: PromptCategory, known_keys: set[str] | None = None
    ) -> list[InterviewQuestion]:
        if mode == PromptMode.BASIC:
            return []
        category_questions = CATEGORY_QUESTIONS[category]
        if mode == PromptMode.PRO:
            questions = [*category_questions[:2], *COMMON_QUESTIONS[:2]]
        else:
            questions = [*category_questions, *COMMON_QUESTIONS, *EXPERT_QUESTIONS][: self.MAX_EXPERT_QUESTIONS]
        return [question for question in questions if question.key not in (known_keys or set())]
