from datetime import datetime
from uuid import UUID

from sqlalchemy import case, func, select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.modules.credits.model import (
    CreditCostRule,
    CreditLot,
    CreditPackage,
    CreditReservation,
    CreditReservationAllocation,
    CreditTransaction,
    CreditWallet,
)


class CreditRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def lock_user(self, user_id: UUID) -> None:
        if self.session.bind and self.session.bind.dialect.name == "postgresql":
            key = int.from_bytes(user_id.bytes[:8], "big", signed=True)
            await self.session.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": key})

    async def wallet(self, user_id: UUID, *, for_update: bool = False) -> CreditWallet | None:
        statement = select(CreditWallet).where(CreditWallet.user_id == user_id)
        if for_update:
            statement = statement.with_for_update()
        return await self.session.scalar(statement)

    async def transaction_by_key(self, key: str) -> CreditTransaction | None:
        return await self.session.scalar(select(CreditTransaction).where(CreditTransaction.idempotency_key == key))

    async def reservation_by_key(self, key: str) -> CreditReservation | None:
        return await self.session.scalar(
            select(CreditReservation)
            .options(selectinload(CreditReservation.allocations).selectinload(CreditReservationAllocation.lot))
            .where(CreditReservation.idempotency_key == key)
        )

    async def reservation(self, reservation_id: UUID) -> CreditReservation | None:
        return await self.session.scalar(
            select(CreditReservation)
            .options(selectinload(CreditReservation.allocations).selectinload(CreditReservationAllocation.lot))
            .where(CreditReservation.id == reservation_id)
        )

    async def spendable_lots(self, wallet_id: UUID, now: datetime) -> list[CreditLot]:
        return list(
            (
                await self.session.scalars(
                    select(CreditLot)
                    .where(
                        CreditLot.wallet_id == wallet_id,
                        CreditLot.available_amount > 0,
                        (CreditLot.expires_at.is_(None) | (CreditLot.expires_at > now)),
                    )
                    .order_by(CreditLot.expires_at.is_(None), CreditLot.expires_at, CreditLot.created_at)
                    .with_for_update()
                )
            ).all()
        )

    async def expired_lots(self, wallet_id: UUID, now: datetime) -> list[CreditLot]:
        return list(
            (
                await self.session.scalars(
                    select(CreditLot).where(
                        CreditLot.wallet_id == wallet_id,
                        CreditLot.available_amount > 0,
                        CreditLot.expires_at.is_not(None),
                        CreditLot.expires_at <= now,
                    )
                )
            ).all()
        )

    async def list_transactions(self, user_id: UUID, offset: int, limit: int) -> tuple[list[CreditTransaction], int]:
        items = list(
            (
                await self.session.scalars(
                    select(CreditTransaction)
                    .where(CreditTransaction.user_id == user_id)
                    .order_by(CreditTransaction.created_at.desc())
                    .offset(offset)
                    .limit(limit)
                )
            ).all()
        )
        total = await self.session.scalar(
            select(func.count()).select_from(CreditTransaction).where(CreditTransaction.user_id == user_id)
        )
        return items, total or 0

    async def seed_defaults(self, packages: tuple[object, ...], rules: tuple[object, ...]) -> None:
        package_codes = set((await self.session.scalars(select(CreditPackage.code))).all())
        for item in packages:
            if item.code not in package_codes:
                self.session.add(CreditPackage(**item.__dict__))
        existing_rules = set(
            (
                await self.session.execute(
                    select(CreditCostRule.operation_type, CreditCostRule.provider, CreditCostRule.model)
                )
            ).all()
        )
        for item in rules:
            identity = (item.operation_type, item.provider, item.model)
            if identity not in existing_rules:
                self.session.add(CreditCostRule(**item.__dict__))
        await self.session.commit()

    async def packages(self, *, active_only: bool) -> list[CreditPackage]:
        statement = select(CreditPackage)
        if active_only:
            statement = statement.where(CreditPackage.is_active.is_(True))
        return list(
            (await self.session.scalars(statement.order_by(CreditPackage.sort_order, CreditPackage.code))).all()
        )

    async def cost_rules(self, *, active_only: bool) -> list[CreditCostRule]:
        statement = select(CreditCostRule)
        if active_only:
            statement = statement.where(CreditCostRule.is_active.is_(True))
        return list(
            (
                await self.session.scalars(statement.order_by(CreditCostRule.operation_type, CreditCostRule.provider))
            ).all()
        )

    async def cost_rule(self, operation_type: str, provider: str, model: str | None) -> CreditCostRule | None:
        return await self.session.scalar(
            select(CreditCostRule)
            .where(
                CreditCostRule.operation_type == operation_type,
                CreditCostRule.provider == provider,
                CreditCostRule.is_active.is_(True),
                (CreditCostRule.model == model) | CreditCostRule.model.is_(None),
            )
            .order_by(case((CreditCostRule.model == model, 0), else_=1))
        )

    async def get_package(self, package_id: UUID) -> CreditPackage | None:
        return await self.session.get(CreditPackage, package_id)

    async def get_cost_rule(self, rule_id: UUID) -> CreditCostRule | None:
        return await self.session.get(CreditCostRule, rule_id)
