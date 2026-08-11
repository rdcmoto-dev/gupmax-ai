from dataclasses import dataclass
from decimal import Decimal

from app.modules.credits.enums import CreditOperationType

DEFAULT_TRIAL_CREDITS = 100


@dataclass(frozen=True)
class PackageDefault:
    code: str
    name: str
    credits: int
    price: Decimal
    currency: str = "BRL"
    bonus_credits: int = 0
    sort_order: int = 0


INITIAL_PACKAGES = (
    PackageDefault("CREDITS_500", "500 créditos", 500, Decimal("19.90"), sort_order=10),
    PackageDefault("CREDITS_1500", "1.500 créditos", 1_500, Decimal("49.90"), bonus_credits=100, sort_order=20),
    PackageDefault("CREDITS_5000", "5.000 créditos", 5_000, Decimal("149.90"), bonus_credits=500, sort_order=30),
    PackageDefault(
        "CREDITS_10000", "10.000 créditos", 10_000, Decimal("269.90"), bonus_credits=1_500, sort_order=40
    ),
)


@dataclass(frozen=True)
class CostRuleDefault:
    operation_type: CreditOperationType
    provider: str
    model: str | None
    base_credit_cost: int
    input_token_rate: Decimal
    output_token_rate: Decimal
    minimum_credit_cost: int


INITIAL_COST_RULES = (
    CostRuleDefault(CreditOperationType.PROMPT_OPTIMIZATION, "openai", None, 1, Decimal("0.001"), Decimal("0.002"), 1),
    CostRuleDefault(CreditOperationType.TEXT_GENERATION, "openai", None, 1, Decimal("0.001"), Decimal("0.002"), 1),
)


PLAN_CREDIT_GRANTS = {"FREE": 0, "STARTER": 500, "PRO": 2_000, "BUSINESS": 10_000}
