from enum import StrEnum


class PromptCategory(StrEnum):
    MARKETING = "marketing"
    SALES = "vendas"
    SOCIAL_MEDIA = "redes_sociais"
    ECOMMERCE = "ecommerce"
    PROGRAMMING = "programacao"
    BUSINESS = "negocios"
    EDUCATION = "educacao"
    WRITING = "escrita"
    IMAGE = "imagem"
    VIDEO = "video"
    PRODUCTIVITY = "produtividade"
    GENERAL = "geral"


class PromptMode(StrEnum):
    BASIC = "basic"
    PRO = "pro"
    EXPERT = "expert"


class TargetAI(StrEnum):
    GENERIC = "generic"
    CHATGPT = "chatgpt"
    CLAUDE = "claude"
    GEMINI = "gemini"
    MIDJOURNEY = "midjourney"
    IMAGE_GENERATOR = "image_generator"
    VIDEO_GENERATOR = "video_generator"
    CODING_ASSISTANT = "coding_assistant"


class PromptStatus(StrEnum):
    PROCESSING = "processing"
    GENERATED = "generated"
    OPTIMIZED = "optimized"
