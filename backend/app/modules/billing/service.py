from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import DomainError
from app.modules.billing.defaults import DEFAULT_TRIAL_PLAN_CODE, INITIAL_PLANS
from app.modules.billing.enums import PaymentProvider, SubscriptionStatus, TrialStatus
from app.modules.billing.exceptions import EntitlementError, UsageLimitExceeded
from app.modules.billing.model import Plan, Subscription, UsageRecord
from app.modules.billing.repository import BillingRepository
from app.modules.billing.schemas import LimitsRead, MetricLimit, PlanCreate, PlanUpdate


def _utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def month_period(now: datetime) -> tuple[datetime, datetime]:
    now = _utc(now)
    start = datetime(now.year, now.month, 1, tzinfo=UTC)
    end = datetime(now.year + (now.month == 12), 1 if now.month == 12 else now.month + 1, 1, tzinfo=UTC)
    return start, end


class BillingService:
    def __init__(self, session: AsyncSession) -> None:
        self.repository = BillingRepository(session)

    async def ensure_plans(self) -> None:
        await self.repository.seed_plans(INITIAL_PLANS)

    async def provision_trial(self, user_id: UUID, now: datetime | None = None) -> Subscription:
        existing = await self.repository.get_subscription(user_id)
        if existing:
            return existing
        await self.ensure_plans()
        plan = await self.repository.get_plan_by_code(DEFAULT_TRIAL_PLAN_CODE)
        if plan is None:
            raise DomainError("Default trial plan is unavailable", status.HTTP_503_SERVICE_UNAVAILABLE)
        now = _utc(now or datetime.now(UTC))
        trial_end = now + timedelta(days=plan.trial_days)
        try:
            return await self.repository.create_subscription(
                user_id=user_id,
                plan_id=plan.id,
                status=SubscriptionStatus.TRIALING,
                provider=PaymentProvider.INTERNAL,
                started_at=now,
                current_period_start=now,
                current_period_end=trial_end,
                trial_started_at=now,
                trial_ends_at=trial_end,
            )
        except IntegrityError:
            await self.repository.session.rollback()
            existing = await self.repository.get_subscription(user_id)
            if existing is None:
                raise
            return existing

    @staticmethod
    def trial_status(subscription: Subscription, now: datetime | None = None) -> TrialStatus:
        if subscription.trial_started_at is None or subscription.trial_ends_at is None:
            return TrialStatus.NOT_ELIGIBLE
        return (
            TrialStatus.ACTIVE
            if _utc(subscription.trial_ends_at) > _utc(now or datetime.now(UTC))
            else TrialStatus.EXPIRED
        )

    def is_entitled(self, subscription: Subscription, now: datetime) -> bool:
        if not subscription.plan.is_active:
            return False
        if subscription.status == SubscriptionStatus.TRIALING:
            return self.trial_status(subscription, now) == TrialStatus.ACTIVE
        return subscription.status == SubscriptionStatus.ACTIVE and _utc(subscription.current_period_end) > now

    async def get_subscription(self, user_id: UUID) -> Subscription:
        return await self.repository.get_subscription(user_id) or await self.provision_trial(user_id)

    async def limits(self, user_id: UUID, now: datetime | None = None) -> LimitsRead:
        now = _utc(now or datetime.now(UTC))
        subscription = await self.get_subscription(user_id)
        start, end = month_period(now)
        generations, input_tokens, output_tokens = await self.repository.usage_totals(user_id, start, end)
        plan = subscription.plan

        def metric(used: int, limit: int) -> MetricLimit:
            return MetricLimit(used=used, limit=limit, remaining=max(limit - used, 0))

        return LimitsRead(
            plan=plan.code,
            generations=metric(generations, plan.monthly_generation_limit),
            input_tokens=metric(input_tokens, plan.monthly_input_token_limit),
            output_tokens=metric(output_tokens, plan.monthly_output_token_limit),
            period_start=start,
            period_end=end,
            trial=self.trial_status(subscription, now),
        )

    async def reserve_ai_generation(self, user_id: UUID, provider: str) -> UsageRecord:
        now = datetime.now(UTC)
        await self.repository.lock_user(user_id)
        subscription = await self.get_subscription(user_id)
        if not self.is_entitled(subscription, now):
            raise EntitlementError()
        start, end = month_period(now)
        generations, input_tokens, output_tokens = await self.repository.usage_totals(user_id, start, end)
        plan = subscription.plan
        if generations >= plan.monthly_generation_limit:
            raise UsageLimitExceeded("Monthly generation limit reached")
        if input_tokens >= plan.monthly_input_token_limit:
            raise UsageLimitExceeded("Monthly input token limit reached")
        if output_tokens >= plan.monthly_output_token_limit:
            raise UsageLimitExceeded("Monthly output token limit reached")
        return await self.repository.reserve_usage(user_id, provider, now)

    async def create_plan(self, data: PlanCreate) -> Plan:
        if await self.repository.get_plan_by_code(data.code):
            raise DomainError("A plan with this code already exists", status.HTTP_409_CONFLICT)
        return await self.repository.create_plan(**data.model_dump())

    async def update_plan(self, plan_id: UUID, data: PlanUpdate) -> Plan:
        plan = await self.repository.get_plan(plan_id)
        if plan is None:
            raise DomainError("Plan not found", status.HTTP_404_NOT_FOUND)
        return await self.repository.update_plan(plan, **data.model_dump(exclude_unset=True))
