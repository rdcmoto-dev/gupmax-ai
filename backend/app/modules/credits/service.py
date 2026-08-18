from datetime import UTC, datetime
from decimal import ROUND_CEILING, Decimal
from uuid import UUID

from fastapi import status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import DomainError
from app.modules.billing.model import Subscription
from app.modules.credits.defaults import DEFAULT_TRIAL_CREDITS, INITIAL_COST_RULES, INITIAL_PACKAGES
from app.modules.credits.enums import (
    CreditOperationType,
    CreditSource,
    CreditTransactionType,
    ReservationStatus,
)
from app.modules.credits.exceptions import CreditCostRuleNotFound, InsufficientCredits
from app.modules.credits.model import (
    CreditCostRule,
    CreditLot,
    CreditPackage,
    CreditReservation,
    CreditReservationAllocation,
    CreditTransaction,
    CreditWallet,
)
from app.modules.credits.repository import CreditRepository
from app.modules.credits.schemas import CostRuleCreate, CostRuleUpdate, PackageCreate, PackageUpdate


def utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


class CreditCostService:
    @staticmethod
    def calculate(rule: CreditCostRule, input_tokens: int, output_tokens: int) -> int:
        raw = (
            Decimal(rule.base_credit_cost)
            + Decimal(rule.input_token_rate) * input_tokens
            + Decimal(rule.output_token_rate) * output_tokens
        )
        return max(rule.minimum_credit_cost, int(raw.to_integral_value(rounding=ROUND_CEILING)))


class CreditService:
    def __init__(self, session: AsyncSession) -> None:
        self.repository = CreditRepository(session)
        self.session = session

    async def ensure_defaults(self) -> None:
        await self.repository.seed_defaults(INITIAL_PACKAGES, INITIAL_COST_RULES)

    async def ensure_wallet(self, user_id: UUID) -> CreditWallet:
        wallet = await self.repository.wallet(user_id)
        if wallet:
            return wallet
        wallet = CreditWallet(user_id=user_id)
        self.session.add(wallet)
        try:
            await self.session.commit()
            await self.session.refresh(wallet)
            return wallet
        except IntegrityError:
            await self.session.rollback()
            wallet = await self.repository.wallet(user_id)
            if wallet is None:
                raise
            return wallet

    async def _expire(self, wallet: CreditWallet, now: datetime) -> int:
        expired = 0
        for lot in await self.repository.expired_lots(wallet.id, now):
            amount = lot.available_amount
            if not amount:
                continue
            lot.available_amount = 0
            wallet.available_balance -= amount
            expired += amount
            self.session.add(
                CreditTransaction(
                    wallet_id=wallet.id,
                    user_id=wallet.user_id,
                    type=CreditTransactionType.EXPIRATION,
                    amount=-amount,
                    balance_after=wallet.available_balance + wallet.reserved_balance,
                    reference_type="credit_lot",
                    reference_id=str(lot.id),
                    idempotency_key=f"expiration:{lot.id}",
                    description="Expired credits",
                )
            )
        return expired

    async def wallet(self, user_id: UUID) -> CreditWallet:
        wallet = await self.ensure_wallet(user_id)
        await self.repository.lock_user(user_id)
        wallet = await self.repository.wallet(user_id, for_update=True) or wallet
        if await self._expire(wallet, datetime.now(UTC)):
            await self.session.commit()
            await self.session.refresh(wallet)
        return wallet

    async def grant(
        self,
        user_id: UUID,
        amount: int,
        *,
        source: CreditSource,
        transaction_type: CreditTransactionType,
        reference_type: str,
        reference_id: str,
        idempotency_key: str,
        description: str,
        expires_at: datetime | None = None,
        metadata: dict[str, object] | None = None,
    ) -> CreditTransaction:
        if amount <= 0:
            raise DomainError("Credit amount must be positive")
        existing = await self.repository.transaction_by_key(idempotency_key)
        if existing:
            return existing
        await self.ensure_wallet(user_id)
        await self.repository.lock_user(user_id)
        wallet = await self.repository.wallet(user_id, for_update=True)
        if wallet is None:
            raise DomainError("Credit wallet unavailable", status.HTTP_503_SERVICE_UNAVAILABLE)
        existing = await self.repository.transaction_by_key(idempotency_key)
        if existing:
            return existing
        wallet.available_balance += amount
        wallet.lifetime_credited += amount
        lot = CreditLot(
            wallet_id=wallet.id,
            source=source,
            original_amount=amount,
            available_amount=amount,
            reserved_amount=0,
            expires_at=expires_at,
        )
        transaction = CreditTransaction(
            wallet_id=wallet.id,
            user_id=user_id,
            type=transaction_type,
            amount=amount,
            balance_after=wallet.available_balance + wallet.reserved_balance,
            reference_type=reference_type,
            reference_id=reference_id,
            idempotency_key=idempotency_key,
            description=description,
            transaction_metadata=metadata,
            expires_at=expires_at,
        )
        self.session.add_all([lot, transaction])
        await self.session.commit()
        await self.session.refresh(transaction)
        return transaction

    async def grant_trial(self, subscription: Subscription) -> CreditTransaction:
        if subscription.trial_ends_at is None:
            raise DomainError("Subscription is not eligible for trial credits")
        return await self.grant(
            subscription.user_id,
            DEFAULT_TRIAL_CREDITS,
            source=CreditSource.TRIAL,
            transaction_type=CreditTransactionType.TRIAL_GRANT,
            reference_type="subscription_trial",
            reference_id=str(subscription.id),
            idempotency_key=f"trial:{subscription.id}",
            description="Trial credit grant",
            expires_at=subscription.trial_ends_at,
        )

    async def grant_plan_period(self, subscription: Subscription) -> CreditTransaction | None:
        amount = subscription.plan.monthly_credit_grant
        if amount <= 0:
            return None
        period_key = utc(subscription.current_period_start).date().isoformat()
        return await self.grant(
            subscription.user_id,
            amount,
            source=CreditSource.PLAN,
            transaction_type=CreditTransactionType.PLAN_GRANT,
            reference_type="subscription_period",
            reference_id=f"{subscription.id}:{period_key}",
            idempotency_key=f"plan:{subscription.id}:{period_key}",
            description=f"Plan {subscription.plan.code} credit grant",
            expires_at=subscription.current_period_end,
        )

    async def rule(self, operation: CreditOperationType, provider: str, model: str | None) -> CreditCostRule:
        await self.ensure_defaults()
        rule = await self.repository.cost_rule(operation, provider, model)
        if rule is None:
            raise CreditCostRuleNotFound()
        return rule

    async def estimate(
        self,
        user_id: UUID,
        operation: CreditOperationType,
        provider: str,
        model: str | None,
        input_tokens: int,
        output_tokens: int,
    ) -> tuple[int, CreditWallet]:
        rule = await self.rule(operation, provider, model)
        return CreditCostService.calculate(rule, input_tokens, output_tokens), await self.wallet(user_id)

    async def _allocate(self, wallet: CreditWallet, reservation: CreditReservation, amount: int, now: datetime) -> None:
        remaining = amount
        for lot in await self.repository.spendable_lots(wallet.id, now):
            taken = min(lot.available_amount, remaining)
            if not taken:
                continue
            lot.available_amount -= taken
            lot.reserved_amount += taken
            self.session.add(CreditReservationAllocation(reservation_id=reservation.id, lot_id=lot.id, amount=taken))
            remaining -= taken
            if remaining == 0:
                break
        if remaining:
            raise InsufficientCredits()

    async def reserve(
        self,
        user_id: UUID,
        operation: CreditOperationType,
        provider: str,
        model: str | None,
        estimated_input_tokens: int,
        max_output_tokens: int,
        idempotency_key: str,
        *,
        purpose: str | None = None,
    ) -> CreditReservation:
        existing = await self.repository.reservation_by_key(idempotency_key)
        if existing:
            return existing
        rule = await self.rule(operation, provider, model)
        amount = CreditCostService.calculate(rule, estimated_input_tokens, max_output_tokens)
        await self.ensure_wallet(user_id)
        await self.repository.lock_user(user_id)
        existing = await self.repository.reservation_by_key(idempotency_key)
        if existing:
            return existing
        wallet = await self.repository.wallet(user_id, for_update=True)
        if wallet is None:
            raise DomainError("Credit wallet unavailable", status.HTTP_503_SERVICE_UNAVAILABLE)
        await self._expire(wallet, datetime.now(UTC))
        if wallet.available_balance < amount:
            await self.session.commit()
            raise InsufficientCredits()
        reservation = CreditReservation(
            wallet_id=wallet.id,
            user_id=user_id,
            operation_type=operation,
            idempotency_key=idempotency_key,
            reserved_credits=amount,
            status=ReservationStatus.RESERVED,
        )
        self.session.add(reservation)
        await self.session.flush()
        await self._allocate(wallet, reservation, amount, datetime.now(UTC))
        wallet.available_balance -= amount
        wallet.reserved_balance += amount
        self.session.add(
            CreditTransaction(
                wallet_id=wallet.id,
                user_id=user_id,
                type=CreditTransactionType.RESERVATION,
                amount=0,
                balance_after=wallet.available_balance + wallet.reserved_balance,
                reference_type="credit_reservation",
                reference_id=str(reservation.id),
                idempotency_key=f"reservation:{idempotency_key}",
                description=f"Reserved credits for {operation.value}",
                transaction_metadata={"reserved_credits": amount, **({"purpose": purpose} if purpose else {})},
            )
        )
        await self.session.commit()
        return await self.repository.reservation_by_key(idempotency_key)  # type: ignore[return-value]

    async def release(self, reservation_id: UUID) -> CreditReservation:
        reservation = await self.repository.reservation(reservation_id)
        if reservation is None:
            raise DomainError("Credit reservation not found", status.HTTP_404_NOT_FOUND)
        if reservation.status != ReservationStatus.RESERVED:
            return reservation
        await self.repository.lock_user(reservation.user_id)
        current_status = await self.session.scalar(
            select(CreditReservation.status).where(CreditReservation.id == reservation.id)
        )
        if current_status != ReservationStatus.RESERVED:
            reservation.status = current_status
            return reservation
        wallet = await self.repository.wallet(reservation.user_id, for_update=True)
        if wallet is None:
            raise DomainError("Credit wallet unavailable", status.HTTP_503_SERVICE_UNAVAILABLE)
        for allocation in reservation.allocations:
            allocation.lot.reserved_amount -= allocation.amount
            allocation.lot.available_amount += allocation.amount
        wallet.reserved_balance -= reservation.reserved_credits
        wallet.available_balance += reservation.reserved_credits
        reservation.status = ReservationStatus.RELEASED
        reservation.settled_at = datetime.now(UTC)
        self.session.add(
            CreditTransaction(
                wallet_id=wallet.id,
                user_id=wallet.user_id,
                type=CreditTransactionType.RESERVATION_RELEASE,
                amount=0,
                balance_after=wallet.available_balance + wallet.reserved_balance,
                reference_type="credit_reservation",
                reference_id=str(reservation.id),
                idempotency_key=f"release:{reservation.id}",
                description="Released credit reservation",
                transaction_metadata={"released_credits": reservation.reserved_credits},
            )
        )
        await self.session.commit()
        return reservation

    async def settle(
        self,
        reservation_id: UUID,
        provider: str,
        model: str | None,
        input_tokens: int,
        output_tokens: int,
        *,
        effective_provider: str | None = None,
        effective_model: str | None = None,
        purpose: str | None = None,
    ) -> CreditReservation:
        reservation = await self.repository.reservation(reservation_id)
        if reservation is None:
            raise DomainError("Credit reservation not found", status.HTTP_404_NOT_FOUND)
        if reservation.status != ReservationStatus.RESERVED:
            return reservation
        rule = await self.rule(reservation.operation_type, provider, model)
        calculated = CreditCostService.calculate(rule, input_tokens, output_tokens)
        await self.repository.lock_user(reservation.user_id)
        current_status = await self.session.scalar(
            select(CreditReservation.status).where(CreditReservation.id == reservation.id)
        )
        if current_status != ReservationStatus.RESERVED:
            reservation.status = current_status
            return reservation
        wallet = await self.repository.wallet(reservation.user_id, for_update=True)
        if wallet is None:
            raise DomainError("Credit wallet unavailable", status.HTTP_503_SERVICE_UNAVAILABLE)
        final_cost = min(calculated, reservation.reserved_credits)
        to_consume = final_cost
        for allocation in reservation.allocations:
            consumed = min(allocation.amount, to_consume)
            released = allocation.amount - consumed
            allocation.lot.reserved_amount -= allocation.amount
            allocation.lot.available_amount += released
            to_consume -= consumed
        released_total = reservation.reserved_credits - final_cost
        wallet.reserved_balance -= reservation.reserved_credits
        wallet.available_balance += released_total
        wallet.lifetime_spent += final_cost
        reservation.status = ReservationStatus.SETTLED
        reservation.settled_credits = final_cost
        reservation.settled_at = datetime.now(UTC)
        self.session.add(
            CreditTransaction(
                wallet_id=wallet.id,
                user_id=wallet.user_id,
                type=CreditTransactionType.AI_USAGE,
                amount=-final_cost,
                balance_after=wallet.available_balance + wallet.reserved_balance,
                reference_type="credit_reservation",
                reference_id=str(reservation.id),
                idempotency_key=f"settlement:{reservation.id}",
                description=f"AI usage: {reservation.operation_type.value}",
                transaction_metadata={
                    "provider": effective_provider or provider,
                    "model": effective_model or model,
                    "input_tokens": input_tokens,
                    "output_tokens": output_tokens,
                    "calculated_credits": calculated,
                    "charged_credits": final_cost,
                    **({"purpose": purpose} if purpose else {}),
                },
            )
        )
        if released_total:
            self.session.add(
                CreditTransaction(
                    wallet_id=wallet.id,
                    user_id=wallet.user_id,
                    type=CreditTransactionType.RESERVATION_RELEASE,
                    amount=0,
                    balance_after=wallet.available_balance + wallet.reserved_balance,
                    reference_type="credit_reservation",
                    reference_id=str(reservation.id),
                    idempotency_key=f"settlement-release:{reservation.id}",
                    description="Released excess credit reservation",
                    transaction_metadata={"released_credits": released_total},
                )
            )
        await self.session.commit()
        return reservation

    async def adjustment(self, user_id: UUID, amount: int, reason: str, key: str) -> CreditTransaction:
        if amount == 0:
            raise DomainError("Adjustment amount cannot be zero")
        if amount > 0:
            return await self.grant(
                user_id,
                amount,
                source=CreditSource.PROMOTIONAL,
                transaction_type=CreditTransactionType.ADJUSTMENT,
                reference_type="admin_adjustment",
                reference_id=key,
                idempotency_key=f"adjustment:{key}",
                description=reason,
            )
        idempotency_key = f"adjustment:{key}"
        existing = await self.repository.transaction_by_key(idempotency_key)
        if existing:
            return existing
        await self.ensure_wallet(user_id)
        await self.repository.lock_user(user_id)
        wallet = await self.repository.wallet(user_id, for_update=True)
        if wallet is None:
            raise DomainError("Credit wallet unavailable", status.HTTP_503_SERVICE_UNAVAILABLE)
        now = datetime.now(UTC)
        await self._expire(wallet, now)
        debit = -amount
        if wallet.available_balance < debit:
            await self.session.commit()
            raise InsufficientCredits()
        remaining = debit
        for lot in await self.repository.spendable_lots(wallet.id, now):
            consumed = min(lot.available_amount, remaining)
            lot.available_amount -= consumed
            remaining -= consumed
            if remaining == 0:
                break
        wallet.available_balance -= debit
        wallet.lifetime_spent += debit
        transaction = CreditTransaction(
            wallet_id=wallet.id,
            user_id=user_id,
            type=CreditTransactionType.ADJUSTMENT,
            amount=amount,
            balance_after=wallet.available_balance + wallet.reserved_balance,
            reference_type="admin_adjustment",
            reference_id=key,
            idempotency_key=idempotency_key,
            description=reason,
        )
        self.session.add(transaction)
        await self.session.commit()
        await self.session.refresh(transaction)
        return transaction

    async def refund(self, user_id: UUID, amount: int, reservation_id: UUID, idempotency_key: str) -> CreditTransaction:
        return await self.grant(
            user_id,
            amount,
            source=CreditSource.PURCHASED,
            transaction_type=CreditTransactionType.REFUND,
            reference_type="credit_reservation",
            reference_id=str(reservation_id),
            idempotency_key=f"refund:{idempotency_key}",
            description="Credit refund",
        )

    async def create_package(self, data: PackageCreate) -> CreditPackage:
        package = CreditPackage(**data.model_dump())
        self.session.add(package)
        await self.session.commit()
        await self.session.refresh(package)
        return package

    async def update_package(self, package_id: UUID, data: PackageUpdate) -> CreditPackage:
        package = await self.repository.get_package(package_id)
        if package is None:
            raise DomainError("Credit package not found", status.HTTP_404_NOT_FOUND)
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(package, field, value)
        await self.session.commit()
        await self.session.refresh(package)
        return package

    async def create_cost_rule(self, data: CostRuleCreate) -> CreditCostRule:
        rule = CreditCostRule(**data.model_dump())
        self.session.add(rule)
        await self.session.commit()
        await self.session.refresh(rule)
        return rule

    async def update_cost_rule(self, rule_id: UUID, data: CostRuleUpdate) -> CreditCostRule:
        rule = await self.repository.get_cost_rule(rule_id)
        if rule is None:
            raise DomainError("Credit cost rule not found", status.HTTP_404_NOT_FOUND)
        for field, value in data.model_dump(exclude_unset=True).items():
            setattr(rule, field, value)
        await self.session.commit()
        await self.session.refresh(rule)
        return rule
