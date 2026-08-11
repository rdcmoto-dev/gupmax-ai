from dataclasses import dataclass
from decimal import Decimal

from app.modules.billing.enums import BillingInterval

DEFAULT_TRIAL_DAYS = 5
DEFAULT_TRIAL_PLAN_CODE = "STARTER"


@dataclass(frozen=True)
class PlanDefault:
    code: str
    name: str
    description: str
    price: Decimal
    currency: str
    billing_interval: BillingInterval
    trial_days: int
    monthly_generation_limit: int
    monthly_input_token_limit: int
    monthly_output_token_limit: int


INITIAL_PLANS = (
    PlanDefault(
        "FREE", "Free", "Uso básico sem otimização por IA.", Decimal("0.00"), "BRL", BillingInterval.MONTH, 0, 0, 0, 0
    ),
    PlanDefault(
        "STARTER",
        "Starter",
        "Plano inicial para uso individual.",
        Decimal("29.90"),
        "BRL",
        BillingInterval.MONTH,
        DEFAULT_TRIAL_DAYS,
        100,
        100_000,
        40_000,
    ),
    PlanDefault(
        "PRO",
        "Pro",
        "Limites ampliados para uso profissional.",
        Decimal("79.90"),
        "BRL",
        BillingInterval.MONTH,
        DEFAULT_TRIAL_DAYS,
        1_000,
        500_000,
        200_000,
    ),
    PlanDefault(
        "BUSINESS",
        "Business",
        "Capacidade para equipes e alto volume.",
        Decimal("249.90"),
        "BRL",
        BillingInterval.MONTH,
        DEFAULT_TRIAL_DAYS,
        5_000,
        3_000_000,
        1_000_000,
    ),
)
