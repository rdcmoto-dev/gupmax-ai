from enum import StrEnum


class PaymentsEnvironment(StrEnum):
    TEST = "test"
    SANDBOX = "sandbox"
    PRODUCTION = "production"


class PaymentProviderName(StrEnum):
    STRIPE = "stripe"
    MERCADO_PAGO = "mercado_pago"


class PaymentPurpose(StrEnum):
    CREDIT_PURCHASE = "credit_purchase"
    SUBSCRIPTION = "subscription"


class PaymentStatus(StrEnum):
    PENDING = "pending"
    PROCESSING = "processing"
    PAID = "paid"
    FAILED = "failed"
    CANCELED = "canceled"
    REFUNDED = "refunded"


class EventProcessingStatus(StrEnum):
    RECEIVED = "received"
    PROCESSING = "processing"
    PROCESSED = "processed"
    IGNORED = "ignored"
    FAILED = "failed"
