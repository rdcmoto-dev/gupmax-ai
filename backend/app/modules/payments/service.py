import hashlib
import logging
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from uuid import UUID

from fastapi import status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.exceptions import DomainError
from app.modules.billing.enums import PaymentProvider as BillingPaymentProvider
from app.modules.billing.enums import SubscriptionStatus
from app.modules.billing.model import Plan
from app.modules.billing.repository import BillingRepository
from app.modules.credits.enums import CreditSource, CreditTransactionType
from app.modules.credits.model import CreditPackage
from app.modules.credits.service import CreditService
from app.modules.payments.contracts import CheckoutInput, ProviderPayment
from app.modules.payments.dependencies import PaymentProviderRegistry
from app.modules.payments.enums import (
    EventProcessingStatus,
    PaymentProviderName,
    PaymentPurpose,
    PaymentStatus,
)
from app.modules.payments.model import Payment, PaymentEvent
from app.modules.payments.repository import PaymentRepository
from app.modules.users.model import User
from app.modules.users.roles import Role

logger = logging.getLogger(__name__)


def enum_value(value: object) -> str:
    return str(getattr(value, "value", value))


class PaymentStateMachine:
    allowed = {
        PaymentStatus.PENDING: {
            PaymentStatus.PROCESSING,
            PaymentStatus.PAID,
            PaymentStatus.FAILED,
            PaymentStatus.CANCELED,
        },
        PaymentStatus.PROCESSING: {PaymentStatus.PAID, PaymentStatus.FAILED, PaymentStatus.CANCELED},
        PaymentStatus.PAID: {PaymentStatus.REFUNDED},
        PaymentStatus.FAILED: set(),
        PaymentStatus.CANCELED: set(),
        PaymentStatus.REFUNDED: set(),
    }

    @classmethod
    def can_transition(cls, current: PaymentStatus, target: PaymentStatus) -> bool:
        return current == target or target in cls.allowed[current]


class PaymentService:
    def __init__(self, session: AsyncSession, registry: PaymentProviderRegistry) -> None:
        self.session = session
        self.repository = PaymentRepository(session)
        self.registry = registry
        self.billing = BillingRepository(session)
        self.credits = CreditService(session)

    async def _create_checkout(
        self,
        user: User,
        provider_name: PaymentProviderName,
        purpose: PaymentPurpose,
        amount: Decimal,
        currency: str,
        title: str,
        idempotency_key: str,
        *,
        package_id: UUID | None = None,
        plan_id: UUID | None = None,
        recurring: bool = False,
        interval: str | None = None,
    ) -> Payment:
        scoped_key = f"{user.id}:{purpose.value}:{idempotency_key}"
        payment = await self.repository.payment_by_key(scoped_key)
        if payment and payment.checkout_url:
            return payment
        if payment is None:
            payment = Payment(
                user_id=user.id,
                provider=provider_name,
                purpose=purpose,
                status=PaymentStatus.PENDING,
                amount=amount,
                currency=currency,
                credit_package_id=package_id,
                plan_id=plan_id,
                idempotency_key=scoped_key,
            )
            self.session.add(payment)
            await self.session.commit()
            await self.session.refresh(payment)
        provider = self.registry.get(provider_name)
        settings = get_settings()
        try:
            checkout = await provider.create_checkout(
                CheckoutInput(
                    internal_payment_id=str(payment.id),
                    idempotency_key=scoped_key,
                    title=title,
                    amount=amount,
                    currency=currency,
                    customer_email=user.email,
                    success_url=f"{settings.frontend_url.rstrip('/')}/payments/success",
                    cancel_url=f"{settings.frontend_url.rstrip('/')}/payments/cancel",
                    webhook_url=(
                        f"{settings.app_public_url.rstrip('/')}/api/v1/payments/webhooks/"
                        f"{'stripe' if provider_name == PaymentProviderName.STRIPE else 'mercado-pago'}"
                    ),
                    recurring=recurring,
                    interval=interval,
                )
            )
        except Exception:
            payment.status = PaymentStatus.FAILED
            payment.failed_at = datetime.now(UTC)
            await self.session.commit()
            logger.warning("payment_checkout_failed", extra={"payment_id": str(payment.id), "provider": provider_name})
            raise
        payment.status = PaymentStatus.PENDING
        payment.failed_at = None
        payment.provider_checkout_id = checkout.checkout_id
        payment.provider_payment_id = checkout.payment_id
        payment.checkout_url = checkout.checkout_url
        await self.session.commit()
        await self.session.refresh(payment)
        logger.info("payment_checkout_created", extra={"payment_id": str(payment.id), "provider": provider_name})
        return payment

    async def credit_checkout(self, user: User, package_id: UUID, provider: PaymentProviderName, key: str) -> Payment:
        package = await self.session.get(CreditPackage, package_id)
        if package is None or not package.is_active:
            raise DomainError("Credit package not found", status.HTTP_404_NOT_FOUND)
        return await self._create_checkout(
            user,
            provider,
            PaymentPurpose.CREDIT_PURCHASE,
            package.price,
            package.currency,
            package.name,
            key,
            package_id=package.id,
        )

    async def subscription_checkout(
        self, user: User, plan_id: UUID, provider: PaymentProviderName, key: str
    ) -> Payment:
        plan = await self.session.get(Plan, plan_id)
        if plan is None or not plan.is_active:
            raise DomainError("Plan not found", status.HTTP_404_NOT_FOUND)
        subscription = await self.billing.get_subscription(user.id)
        if subscription and subscription.status == SubscriptionStatus.ACTIVE:
            raise DomainError("Active subscription changes require support", status.HTTP_409_CONFLICT)
        return await self._create_checkout(
            user,
            provider,
            PaymentPurpose.SUBSCRIPTION,
            plan.price,
            plan.currency,
            plan.name,
            key,
            plan_id=plan.id,
            recurring=True,
            interval=enum_value(plan.billing_interval),
        )

    async def accessible(self, payment_id: UUID, user: User) -> Payment:
        payment = await self.repository.payment(payment_id)
        if payment is None or (payment.user_id != user.id and user.role != Role.ADMIN):
            raise DomainError("Payment not found", status.HTTP_404_NOT_FOUND)
        return payment

    async def _apply_paid(self, payment: Payment, remote: ProviderPayment) -> None:
        amount_mismatch = remote.amount != payment.amount and not (
            payment.purpose == PaymentPurpose.SUBSCRIPTION and remote.amount == 0
        )
        if amount_mismatch or remote.currency.upper() != payment.currency.upper():
            payment.status = PaymentStatus.FAILED
            payment.failed_at = datetime.now(UTC)
            await self.session.commit()
            raise DomainError("Payment confirmation mismatch", status.HTTP_409_CONFLICT)
        if payment.purpose == PaymentPurpose.CREDIT_PURCHASE:
            package = await self.session.get(CreditPackage, payment.credit_package_id)
            if package is None:
                raise DomainError("Payment product unavailable", status.HTTP_409_CONFLICT)
            await self.credits.grant(
                payment.user_id,
                package.credits + package.bonus_credits,
                source=CreditSource.PURCHASED,
                transaction_type=CreditTransactionType.PURCHASE,
                reference_type="payment",
                reference_id=str(payment.id),
                idempotency_key=f"purchase:{enum_value(payment.provider)}:{remote.payment_id}",
                description=f"Credit purchase: {package.code}",
                metadata={"payment_id": str(payment.id), "package_code": package.code},
            )
        else:
            await self._activate_subscription(payment, remote)
        payment.provider_payment_id = remote.payment_id
        payment.status = PaymentStatus.PAID
        payment.paid_at = datetime.now(UTC)
        await self.session.commit()

    async def _activate_subscription(self, payment: Payment, remote: ProviderPayment) -> None:
        plan = await self.session.get(Plan, payment.plan_id)
        subscription = await self.billing.get_subscription(payment.user_id)
        if plan is None or subscription is None or not remote.subscription_id:
            raise DomainError("Subscription confirmation is incomplete", status.HTTP_409_CONFLICT)
        now = datetime.now(UTC)
        subscription.plan_id = plan.id
        subscription.plan = plan
        subscription.status = SubscriptionStatus.ACTIVE
        subscription.provider = BillingPaymentProvider(enum_value(payment.provider))
        subscription.provider_customer_id = remote.customer_id
        subscription.provider_subscription_id = remote.subscription_id
        subscription.started_at = remote.period_start or now
        subscription.current_period_start = remote.period_start or now
        subscription.current_period_end = remote.period_end or now + timedelta(days=30)
        subscription.cancel_at_period_end = False
        await self.session.commit()
        await self.credits.grant_plan_period(subscription)

    async def process_webhook(
        self,
        provider_name: PaymentProviderName,
        payload: bytes,
        headers: dict[str, str],
        query: dict[str, str],
    ) -> None:
        provider = self.registry.get(provider_name)
        notification = provider.verify_webhook(payload, headers, query)
        event_key = f"{provider_name.value}:{notification.event_id}"
        event = await self.repository.event(event_key)
        if event and event.processing_status in {EventProcessingStatus.PROCESSED, EventProcessingStatus.IGNORED}:
            return
        if event is None:
            event = PaymentEvent(
                provider=provider_name,
                provider_event_id=event_key,
                event_type=notification.event_type,
                payload_hash=hashlib.sha256(payload).hexdigest(),
                processing_status=EventProcessingStatus.RECEIVED,
            )
            self.session.add(event)
        event.processing_status = EventProcessingStatus.PROCESSING
        await self.session.commit()
        try:
            remote = await provider.get_payment(notification.resource_id)
            payment = await self.repository.payment_by_provider_reference(
                provider_name, notification.resource_id, remote.internal_payment_id
            )
            if payment is None:
                event.processing_status = EventProcessingStatus.IGNORED
            elif not PaymentStateMachine.can_transition(payment.status, remote.status):
                event.processing_status = EventProcessingStatus.IGNORED
            elif remote.status == PaymentStatus.PAID:
                await self._apply_paid(payment, remote)
                event.processing_status = EventProcessingStatus.PROCESSED
            else:
                payment.status = remote.status
                now = datetime.now(UTC)
                if remote.status == PaymentStatus.FAILED:
                    payment.failed_at = now
                elif remote.status == PaymentStatus.CANCELED:
                    payment.canceled_at = now
                event.processing_status = EventProcessingStatus.PROCESSED
            event.processed_at = datetime.now(UTC)
            event.error_message = None
            await self.session.commit()
        except Exception as exc:
            await self.session.rollback()
            event = await self.repository.event(event_key)
            if event:
                event.processing_status = EventProcessingStatus.FAILED
                event.error_message = type(exc).__name__
                await self.session.commit()
            raise

    async def cancel_subscription(self, user: User) -> bool:
        subscription = await self.billing.get_subscription(user.id)
        if subscription is None or not subscription.provider_subscription_id:
            raise DomainError("External subscription not found", status.HTTP_404_NOT_FOUND)
        try:
            provider_name = PaymentProviderName(enum_value(subscription.provider))
        except ValueError as exc:
            raise DomainError(
                "Subscription cannot be canceled through a payment provider", status.HTTP_409_CONFLICT
            ) from exc
        await self.registry.get(provider_name).cancel_subscription(subscription.provider_subscription_id)
        subscription.cancel_at_period_end = True
        await self.session.commit()
        return True
