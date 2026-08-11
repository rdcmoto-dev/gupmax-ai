from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.modules.billing.enums import BillingInterval, PaymentProvider, SubscriptionStatus, TrialStatus


class PlanBase(BaseModel):
    code: str = Field(min_length=2, max_length=40, pattern=r"^[A-Z][A-Z0-9_]*$")
    name: str = Field(min_length=2, max_length=100)
    description: str = Field(min_length=1, max_length=2_000)
    price: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    currency: str = Field(min_length=3, max_length=3, pattern=r"^[A-Z]{3}$")
    billing_interval: BillingInterval
    trial_days: int = Field(ge=0, le=365)
    monthly_generation_limit: int = Field(ge=0)
    monthly_input_token_limit: int = Field(ge=0)
    monthly_output_token_limit: int = Field(ge=0)
    monthly_credit_grant: int = Field(default=0, ge=0, le=2_000_000_000)
    is_active: bool = True


class PlanCreate(PlanBase):
    pass


class PlanUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=100)
    description: str | None = Field(default=None, min_length=1, max_length=2_000)
    price: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    currency: str | None = Field(default=None, min_length=3, max_length=3, pattern=r"^[A-Z]{3}$")
    billing_interval: BillingInterval | None = None
    trial_days: int | None = Field(default=None, ge=0, le=365)
    monthly_generation_limit: int | None = Field(default=None, ge=0)
    monthly_input_token_limit: int | None = Field(default=None, ge=0)
    monthly_output_token_limit: int | None = Field(default=None, ge=0)
    monthly_credit_grant: int | None = Field(default=None, ge=0, le=2_000_000_000)
    is_active: bool | None = None


class PlanRead(PlanBase):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    created_at: datetime
    updated_at: datetime


class SubscriptionRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    user_id: UUID
    plan: PlanRead
    status: SubscriptionStatus
    provider: PaymentProvider
    started_at: datetime
    current_period_start: datetime
    current_period_end: datetime
    cancel_at_period_end: bool
    canceled_at: datetime | None
    trial_started_at: datetime | None
    trial_ends_at: datetime | None
    trial_status: TrialStatus = TrialStatus.NOT_ELIGIBLE


class UsageRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    prompt_id: UUID | None
    provider: str
    model: str | None
    input_tokens: int
    output_tokens: int
    total_tokens: int
    generation_count: int
    occurred_at: datetime


class UsagePage(BaseModel):
    items: list[UsageRead]
    total: int
    offset: int
    limit: int


class MetricLimit(BaseModel):
    used: int
    limit: int
    remaining: int


class LimitsRead(BaseModel):
    plan: str
    generations: MetricLimit
    input_tokens: MetricLimit
    output_tokens: MetricLimit
    period_start: datetime
    period_end: datetime
    trial: TrialStatus


class UsageTotals(BaseModel):
    generation_count: int = 0
    input_tokens: int = 0
    output_tokens: int = 0

    @field_validator("generation_count", "input_tokens", "output_tokens")
    @classmethod
    def non_negative(cls, value: int) -> int:
        if value < 0:
            raise ValueError("usage cannot be negative")
        return value
