from datetime import datetime
from uuid import UUID

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.modules.billing.model import Plan, Subscription, UsageRecord


class BillingRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def lock_user(self, user_id: UUID) -> None:
        if self.session.bind and self.session.bind.dialect.name == "postgresql":
            lock_key = int.from_bytes(user_id.bytes[:8], "big", signed=True)
            await self.session.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": lock_key})

    async def seed_plans(self, defaults: tuple[object, ...]) -> None:
        existing = set((await self.session.scalars(select(Plan.code))).all())
        for item in defaults:
            if item.code not in existing:
                self.session.add(Plan(**item.__dict__))
        await self.session.commit()

    async def list_plans(self, *, active_only: bool) -> list[Plan]:
        statement = select(Plan)
        if active_only:
            statement = statement.where(Plan.is_active.is_(True))
        return list((await self.session.scalars(statement.order_by(Plan.price, Plan.code))).all())

    async def get_plan_by_code(self, code: str) -> Plan | None:
        return await self.session.scalar(select(Plan).where(Plan.code == code))

    async def get_plan(self, plan_id: UUID) -> Plan | None:
        return await self.session.get(Plan, plan_id)

    async def create_plan(self, **values: object) -> Plan:
        plan = Plan(**values)
        self.session.add(plan)
        await self.session.commit()
        await self.session.refresh(plan)
        return plan

    async def update_plan(self, plan: Plan, **values: object) -> Plan:
        for field, value in values.items():
            setattr(plan, field, value)
        await self.session.commit()
        await self.session.refresh(plan)
        return plan

    async def get_subscription(self, user_id: UUID) -> Subscription | None:
        return await self.session.scalar(
            select(Subscription).options(selectinload(Subscription.plan)).where(Subscription.user_id == user_id)
        )

    async def create_subscription(self, **values: object) -> Subscription:
        subscription = Subscription(**values)
        self.session.add(subscription)
        await self.session.commit()
        return await self.get_subscription(subscription.user_id)  # type: ignore[return-value]

    async def usage_totals(self, user_id: UUID, start: datetime, end: datetime) -> tuple[int, int, int]:
        row = (
            await self.session.execute(
                select(
                    func.coalesce(func.sum(UsageRecord.generation_count), 0),
                    func.coalesce(func.sum(UsageRecord.input_tokens), 0),
                    func.coalesce(func.sum(UsageRecord.output_tokens), 0),
                ).where(
                    UsageRecord.user_id == user_id,
                    UsageRecord.occurred_at >= start,
                    UsageRecord.occurred_at < end,
                )
            )
        ).one()
        return int(row[0]), int(row[1]), int(row[2])

    async def reserve_usage(self, user_id: UUID, provider: str, occurred_at: datetime) -> UsageRecord:
        record = UsageRecord(user_id=user_id, provider=provider, generation_count=1, occurred_at=occurred_at)
        self.session.add(record)
        await self.session.commit()
        await self.session.refresh(record)
        return record

    async def finalize_usage(
        self,
        record: UsageRecord,
        *,
        prompt_id: UUID | None,
        provider: str,
        model: str,
        input_tokens: int,
        output_tokens: int,
    ) -> None:
        record.prompt_id = prompt_id
        record.provider = provider
        record.model = model
        record.input_tokens = input_tokens
        record.output_tokens = output_tokens
        record.total_tokens = input_tokens + output_tokens
        await self.session.commit()

    async def release_usage(self, record: UsageRecord) -> None:
        await self.session.delete(record)
        await self.session.commit()

    async def list_usage(self, user_id: UUID, offset: int, limit: int) -> tuple[list[UsageRecord], int]:
        filters = (UsageRecord.user_id == user_id,)
        items = list(
            (
                await self.session.scalars(
                    select(UsageRecord)
                    .where(*filters)
                    .order_by(UsageRecord.occurred_at.desc())
                    .offset(offset)
                    .limit(limit)
                )
            ).all()
        )
        total = await self.session.scalar(select(func.count()).select_from(UsageRecord).where(*filters))
        return items, total or 0
