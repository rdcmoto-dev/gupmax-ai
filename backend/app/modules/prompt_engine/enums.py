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


class PromptStatus(StrEnum):
    GENERATED = "generated"
    OPTIMIZED = "optimized"
