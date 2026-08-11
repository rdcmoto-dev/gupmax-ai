from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status

from app.modules.credits.dependencies import Credits
from app.modules.credits.schemas import (
    AdjustmentRequest,
    CostRuleCreate,
    CostRuleRead,
    CostRuleUpdate,
    EstimateRequest,
    EstimateResponse,
    PackageCreate,
    PackageRead,
    PackageUpdate,
    TransactionPage,
    TransactionRead,
    WalletRead,
)
from app.modules.users.dependencies import get_current_user, require_permission
from app.modules.users.model import User
from app.modules.users.roles import Permission, Role

router = APIRouter()
CurrentUser = Annotated[User, Depends(get_current_user)]
CreditsAdmin = Annotated[User, Depends(require_permission(Permission.CREDITS_MANAGE))]


@router.get("/wallet", response_model=WalletRead)
async def wallet(credits: Credits, current_user: CurrentUser) -> WalletRead:
    return await credits.wallet(current_user.id)


@router.get("/transactions", response_model=TransactionPage)
async def transactions(
    credits: Credits,
    current_user: CurrentUser,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
) -> TransactionPage:
    items, total = await credits.repository.list_transactions(current_user.id, offset, limit)
    return TransactionPage(items=items, total=total, offset=offset, limit=limit)


@router.get("/packages", response_model=list[PackageRead])
async def packages(credits: Credits, current_user: CurrentUser) -> list[PackageRead]:
    await credits.ensure_defaults()
    return await credits.repository.packages(active_only=current_user.role != Role.ADMIN)


@router.get("/costs", response_model=list[CostRuleRead])
async def costs(credits: Credits, current_user: CurrentUser) -> list[CostRuleRead]:
    await credits.ensure_defaults()
    return await credits.repository.cost_rules(active_only=current_user.role != Role.ADMIN)


@router.post("/estimate", response_model=EstimateResponse)
async def estimate(data: EstimateRequest, credits: Credits, current_user: CurrentUser) -> EstimateResponse:
    amount, user_wallet = await credits.estimate(
        current_user.id,
        data.operation_type,
        data.provider,
        data.model,
        data.estimated_input_tokens,
        data.max_output_tokens,
    )
    return EstimateResponse(
        estimated_credits=amount,
        available_credits=user_wallet.available_balance,
        can_execute=user_wallet.available_balance >= amount,
    )


@router.post("/packages", response_model=PackageRead, status_code=status.HTTP_201_CREATED)
async def create_package(data: PackageCreate, credits: Credits, _: CreditsAdmin) -> PackageRead:
    return await credits.create_package(data)


@router.patch("/packages/{package_id}", response_model=PackageRead)
async def update_package(package_id: UUID, data: PackageUpdate, credits: Credits, _: CreditsAdmin) -> PackageRead:
    return await credits.update_package(package_id, data)


@router.post("/costs", response_model=CostRuleRead, status_code=status.HTTP_201_CREATED)
async def create_cost(data: CostRuleCreate, credits: Credits, _: CreditsAdmin) -> CostRuleRead:
    return await credits.create_cost_rule(data)


@router.patch("/costs/{rule_id}", response_model=CostRuleRead)
async def update_cost(rule_id: UUID, data: CostRuleUpdate, credits: Credits, _: CreditsAdmin) -> CostRuleRead:
    return await credits.update_cost_rule(rule_id, data)


@router.post("/adjustments", response_model=TransactionRead, status_code=status.HTTP_201_CREATED)
async def adjustment(data: AdjustmentRequest, credits: Credits, _: CreditsAdmin) -> TransactionRead:
    return await credits.adjustment(data.user_id, data.amount, data.reason, data.idempotency_key)
