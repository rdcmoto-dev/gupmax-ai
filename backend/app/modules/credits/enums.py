from enum import StrEnum


class CreditSource(StrEnum):
    PLAN = "plan"
    PURCHASED = "purchased"
    TRIAL = "trial"
    PROMOTIONAL = "promotional"


class CreditTransactionType(StrEnum):
    PLAN_GRANT = "plan_grant"
    PURCHASE = "purchase"
    TRIAL_GRANT = "trial_grant"
    PROMOTION = "promotion"
    AI_USAGE = "ai_usage"
    RESERVATION = "reservation"
    RESERVATION_RELEASE = "reservation_release"
    REFUND = "refund"
    ADJUSTMENT = "adjustment"
    EXPIRATION = "expiration"


class CreditOperationType(StrEnum):
    TEXT_GENERATION = "text_generation"
    PROMPT_OPTIMIZATION = "prompt_optimization"
    IMAGE_GENERATION = "image_generation"
    VIDEO_GENERATION = "video_generation"


class ReservationStatus(StrEnum):
    RESERVED = "reserved"
    SETTLED = "settled"
    RELEASED = "released"
