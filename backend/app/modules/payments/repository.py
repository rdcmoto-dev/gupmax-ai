from datetime import datetime
from uuid import UUID

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.payments.enums import PaymentProviderName, PaymentPurpose, PaymentStatus
from app.modules.payments.model import Payment, PaymentEvent


class PaymentRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def payment(self, payment_id: UUID) -> Payment | None:
        return await self.session.get(Payment, payment_id)

    async def payment_for_update(self, payment_id: UUID) -> Payment | None:
        return await self.session.scalar(
            select(Payment)
            .where(Payment.id == payment_id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )

    async def payment_by_key(self, key: str) -> Payment | None:
        return await self.session.scalar(select(Payment).where(Payment.idempotency_key == key))

    async def payment_by_provider_reference(
        self, provider: PaymentProviderName, reference: str, internal_id: str | None
    ) -> Payment | None:
        if internal_id:
            try:
                payment = await self.payment(UUID(internal_id))
                if payment and payment.provider == provider:
                    return payment
            except ValueError:
                pass
        return await self.session.scalar(
            select(Payment).where(
                Payment.provider == provider,
                or_(Payment.provider_payment_id == reference, Payment.provider_checkout_id == reference),
            )
        )

    async def list(
        self,
        *,
        user_id: UUID | None,
        provider: PaymentProviderName | None,
        purpose: PaymentPurpose | None,
        payment_status: PaymentStatus | None,
        created_from: datetime | None,
        created_to: datetime | None,
        offset: int,
        limit: int,
    ) -> tuple[list[Payment], int]:
        filters = []
        if user_id:
            filters.append(Payment.user_id == user_id)
        if provider:
            filters.append(Payment.provider == provider)
        if purpose:
            filters.append(Payment.purpose == purpose)
        if payment_status:
            filters.append(Payment.status == payment_status)
        if created_from:
            filters.append(Payment.created_at >= created_from)
        if created_to:
            filters.append(Payment.created_at <= created_to)
        items = list(
            (
                await self.session.scalars(
                    select(Payment).where(*filters).order_by(Payment.created_at.desc()).offset(offset).limit(limit)
                )
            ).all()
        )
        total = await self.session.scalar(select(func.count()).select_from(Payment).where(*filters))
        return items, total or 0

    async def event(self, provider_event_id: str) -> PaymentEvent | None:
        return await self.session.scalar(
            select(PaymentEvent).where(PaymentEvent.provider_event_id == provider_event_id)
        )
