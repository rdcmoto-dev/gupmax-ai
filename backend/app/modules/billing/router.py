from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status

from app.modules.billing.dependencies import Billing
from app.modules.billing.schemas import LimitsRead, PlanCreate, PlanRead, PlanUpdate, SubscriptionRead, UsagePage
from app.modules.users.dependencies import get_current_user, require_permission
from app.modules.users.model import User
from app.modules.users.roles import Permission, Role

router = APIRouter()
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get("/plans", response_model=list[PlanRead], summary="Lista planos disponíveis")
async def list_plans(billing: Billing, current_user: CurrentUser) -> list[PlanRead]:
    await billing.ensure_plans()
    return await billing.repository.list_plans(active_only=current_user.role != Role.ADMIN)


@router.post("/plans", response_model=PlanRead, status_code=status.HTTP_201_CREATED, summary="Cria um plano")
async def create_plan(
    data: PlanCreate,
    billing: Billing,
    _: Annotated[User, Depends(require_permission(Permission.BILLING_MANAGE))],
) -> PlanRead:
    return await billing.create_plan(data)


@router.patch("/plans/{plan_id}", response_model=PlanRead, summary="Atualiza ou ativa/desativa um plano")
async def update_plan(
    plan_id: UUID,
    data: PlanUpdate,
    billing: Billing,
    _: Annotated[User, Depends(require_permission(Permission.BILLING_MANAGE))],
) -> PlanRead:
    return await billing.update_plan(plan_id, data)


@router.get("/subscription", response_model=SubscriptionRead, summary="Obtém a assinatura atual")
async def get_subscription(billing: Billing, current_user: CurrentUser) -> SubscriptionRead:
    subscription = await billing.get_subscription(current_user.id)
    response = SubscriptionRead.model_validate(subscription)
    return response.model_copy(update={"trial_status": billing.trial_status(subscription)})


@router.get("/usage", response_model=UsagePage, summary="Lista o histórico de uso de IA")
async def get_usage(
    billing: Billing,
    current_user: CurrentUser,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
) -> UsagePage:
    items, total = await billing.repository.list_usage(current_user.id, offset, limit)
    return UsagePage(items=items, total=total, offset=offset, limit=limit)


@router.get("/limits", response_model=LimitsRead, summary="Obtém limites e consumo do período")
async def get_limits(billing: Billing, current_user: CurrentUser) -> LimitsRead:
    return await billing.limits(current_user.id)
