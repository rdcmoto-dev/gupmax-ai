from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, Request, status

from app.modules.payments.dependencies import ProviderRegistry
from app.modules.payments.enums import PaymentProviderName, PaymentPurpose, PaymentStatus
from app.modules.payments.schemas import (
    CancelSubscriptionResponse,
    CheckoutResponse,
    CreditCheckoutRequest,
    PaymentPage,
    PaymentRead,
    SubscriptionCheckoutRequest,
)
from app.modules.payments.service import PaymentService
from app.modules.users.dependencies import DbSession, get_current_user, require_permission
from app.modules.users.model import User
from app.modules.users.roles import Permission, Role

router = APIRouter()
CurrentUser = Annotated[User, Depends(get_current_user)]
PaymentsAdmin = Annotated[User, Depends(require_permission(Permission.PAYMENTS_MANAGE))]
IdempotencyKey = Annotated[str, Header(alias="Idempotency-Key", min_length=8, max_length=200)]


@router.post(
    "/credits/checkout",
    response_model=CheckoutResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Cria checkout hospedado para pacote de créditos",
)
async def credit_checkout(
    data: CreditCheckoutRequest,
    key: IdempotencyKey,
    session: DbSession,
    registry: ProviderRegistry,
    current_user: CurrentUser,
) -> CheckoutResponse:
    payment = await PaymentService(session, registry).credit_checkout(current_user, data.package_id, data.provider, key)
    return CheckoutResponse(
        payment_id=payment.id,
        provider=payment.provider,
        checkout_url=payment.checkout_url,
        status=payment.status,
    )


@router.post(
    "/subscriptions/checkout",
    response_model=CheckoutResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Cria checkout hospedado para assinatura",
)
async def subscription_checkout(
    data: SubscriptionCheckoutRequest,
    key: IdempotencyKey,
    session: DbSession,
    registry: ProviderRegistry,
    current_user: CurrentUser,
) -> CheckoutResponse:
    payment = await PaymentService(session, registry).subscription_checkout(
        current_user, data.plan_id, data.provider, key
    )
    return CheckoutResponse(
        payment_id=payment.id,
        provider=payment.provider,
        checkout_url=payment.checkout_url,
        status=payment.status,
    )


@router.post(
    "/{payment_id}/reconcile/mercado-pago",
    response_model=PaymentRead,
    summary="Reconcilia pagamento Mercado Pago aprovado",
)
async def reconcile_mercado_pago(
    payment_id: UUID,
    session: DbSession,
    registry: ProviderRegistry,
    _: PaymentsAdmin,
) -> PaymentRead:
    return await PaymentService(session, registry).reconcile_mercado_pago(payment_id)


@router.post("/subscriptions/cancel", response_model=CancelSubscriptionResponse, summary="Agenda cancelamento")
async def cancel_subscription(
    session: DbSession, registry: ProviderRegistry, current_user: CurrentUser
) -> CancelSubscriptionResponse:
    await PaymentService(session, registry).cancel_subscription(current_user)
    return CancelSubscriptionResponse(cancel_at_period_end=True)


@router.get("/{payment_id}", response_model=PaymentRead, summary="Consulta pagamento próprio")
async def payment_status(
    payment_id: UUID, session: DbSession, registry: ProviderRegistry, current_user: CurrentUser
) -> PaymentRead:
    return await PaymentService(session, registry).accessible(payment_id, current_user)


@router.get("", response_model=PaymentPage, summary="Lista histórico de pagamentos")
async def payment_history(
    session: DbSession,
    registry: ProviderRegistry,
    current_user: CurrentUser,
    provider: PaymentProviderName | None = None,
    purpose: PaymentPurpose | None = None,
    payment_status: Annotated[PaymentStatus | None, Query(alias="status")] = None,
    created_from: datetime | None = None,
    created_to: datetime | None = None,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
) -> PaymentPage:
    items, total = await PaymentService(session, registry).repository.list(
        user_id=None if current_user.role == Role.ADMIN else current_user.id,
        provider=provider,
        purpose=purpose,
        payment_status=payment_status,
        created_from=created_from,
        created_to=created_to,
        offset=offset,
        limit=limit,
    )
    return PaymentPage(items=items, total=total, offset=offset, limit=limit)


async def _webhook(
    provider: PaymentProviderName, request: Request, session: DbSession, registry: ProviderRegistry
) -> None:
    payload = await request.body()
    await PaymentService(session, registry).process_webhook(
        provider,
        payload,
        {key.lower(): value for key, value in request.headers.items()},
        dict(request.query_params),
    )


@router.post(
    "/webhooks/stripe",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Recebe eventos server-to-server assinados da Stripe",
)
async def stripe_webhook(request: Request, session: DbSession, registry: ProviderRegistry) -> None:
    await _webhook(PaymentProviderName.STRIPE, request, session, registry)


@router.post(
    "/webhooks/mercado-pago",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Recebe notificações server-to-server autenticadas do Mercado Pago",
)
async def mercado_pago_webhook(request: Request, session: DbSession, registry: ProviderRegistry) -> None:
    await _webhook(PaymentProviderName.MERCADO_PAGO, request, session, registry)
