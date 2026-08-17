from enum import StrEnum


class InterviewStatus(StrEnum):
    ACTIVE = "active"
    READY = "ready"
    COMPLETED = "completed"
    EXPIRED = "expired"


class QuestionType(StrEnum):
    TEXT = "text"
    MULTILINE = "multiline"
    SINGLE_CHOICE = "single_choice"
    MULTI_CHOICE = "multi_choice"
    BOOLEAN = "boolean"
