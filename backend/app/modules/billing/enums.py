from enum import StrEnum


class BillingInterval(StrEnum):
    MONTH = "month"
    YEAR = "year"


class SubscriptionStatus(StrEnum):
    TRIALING = "trialing"
    ACTIVE = "active"
    PAST_DUE = "past_due"
    CANCELED = "canceled"
    EXPIRED = "expired"


class PaymentProvider(StrEnum):
    INTERNAL = "internal"
    STRIPE = "stripe"
    MERCADO_PAGO = "mercado_pago"


class TrialStatus(StrEnum):
    ACTIVE = "active"
    EXPIRED = "expired"
    NOT_ELIGIBLE = "not_eligible"
