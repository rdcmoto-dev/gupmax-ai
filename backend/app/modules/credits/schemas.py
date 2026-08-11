from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.modules.credits.enums import CreditOperationType, CreditTransactionType


class WalletRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    available_balance: int
    reserved_balance: int
    lifetime_credited: int
    lifetime_spent: int
    created_at: datetime
    updated_at: datetime


class TransactionRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    type: CreditTransactionType
    amount: int
    balance_after: int
    reference_type: str
    reference_id: str
    description: str
    expires_at: datetime | None
    created_at: datetime


class TransactionPage(BaseModel):
    items: list[TransactionRead]
    total: int
    offset: int
    limit: int


class PackageBase(BaseModel):
    code: str = Field(min_length=3, max_length=50, pattern=r"^[A-Z][A-Z0-9_]*$")
    name: str = Field(min_length=2, max_length=100)
    credits: int = Field(gt=0, le=2_000_000_000)
    price: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    currency: str = Field(min_length=3, max_length=3, pattern=r"^[A-Z]{3}$")
    bonus_credits: int = Field(default=0, ge=0, le=2_000_000_000)
    is_active: bool = True
    sort_order: int = Field(default=0, ge=0)


class PackageCreate(PackageBase):
    pass


class PackageUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=100)
    credits: int | None = Field(default=None, gt=0, le=2_000_000_000)
    price: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    currency: str | None = Field(default=None, min_length=3, max_length=3, pattern=r"^[A-Z]{3}$")
    bonus_credits: int | None = Field(default=None, ge=0, le=2_000_000_000)
    is_active: bool | None = None
    sort_order: int | None = Field(default=None, ge=0)


class PackageRead(PackageBase):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    created_at: datetime
    updated_at: datetime


class CostRuleBase(BaseModel):
    operation_type: CreditOperationType
    provider: str = Field(min_length=1, max_length=50)
    model: str | None = Field(default=None, min_length=1, max_length=200)
    base_credit_cost: int = Field(ge=0)
    input_token_rate: Decimal = Field(ge=0, max_digits=12, decimal_places=6)
    output_token_rate: Decimal = Field(ge=0, max_digits=12, decimal_places=6)
    minimum_credit_cost: int = Field(ge=0)
    is_active: bool = True


class CostRuleCreate(CostRuleBase):
    pass


class CostRuleUpdate(BaseModel):
    base_credit_cost: int | None = Field(default=None, ge=0)
    input_token_rate: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=6)
    output_token_rate: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=6)
    minimum_credit_cost: int | None = Field(default=None, ge=0)
    is_active: bool | None = None


class CostRuleRead(CostRuleBase):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    created_at: datetime
    updated_at: datetime


class EstimateRequest(BaseModel):
    operation_type: CreditOperationType
    provider: str = Field(default="openai", min_length=1, max_length=50)
    model: str | None = Field(default=None, min_length=1, max_length=200)
    estimated_input_tokens: int = Field(default=0, ge=0, le=10_000_000)
    max_output_tokens: int = Field(default=0, ge=0, le=1_000_000)


class EstimateResponse(BaseModel):
    estimated_credits: int
    available_credits: int
    can_execute: bool


class AdjustmentRequest(BaseModel):
    user_id: UUID
    amount: int = Field(ge=-2_000_000_000, le=2_000_000_000)
    reason: str = Field(min_length=5, max_length=500)
    idempotency_key: str = Field(min_length=8, max_length=200)
