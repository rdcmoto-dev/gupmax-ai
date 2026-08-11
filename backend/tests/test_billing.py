from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app.modules.billing.enums import SubscriptionStatus, TrialStatus
from app.modules.billing.schemas import PlanCreate
from app.modules.billing.service import BillingService, month_period
from app.modules.users.roles import Permission, Role, has_permission


def test_month_period_uses_calendar_month() -> None:
    start, end = month_period(datetime(2026, 12, 31, 23, tzinfo=UTC))
    assert start == datetime(2026, 12, 1, tzinfo=UTC)
    assert end == datetime(2027, 1, 1, tzinfo=UTC)


def test_trial_is_calculated_at_read_time() -> None:
    now = datetime(2026, 8, 10, tzinfo=UTC)
    active = SimpleNamespace(trial_started_at=now, trial_ends_at=now + timedelta(days=1))
    expired = SimpleNamespace(trial_started_at=now - timedelta(days=6), trial_ends_at=now - timedelta(days=1))
    ineligible = SimpleNamespace(trial_started_at=None, trial_ends_at=None)
    assert BillingService.trial_status(active, now) == TrialStatus.ACTIVE
    assert BillingService.trial_status(expired, now) == TrialStatus.EXPIRED
    assert BillingService.trial_status(ineligible, now) == TrialStatus.NOT_ELIGIBLE


def test_entitlement_requires_active_plan_and_valid_period() -> None:
    now = datetime(2026, 8, 10, tzinfo=UTC)
    service = BillingService(SimpleNamespace())
    subscription = SimpleNamespace(
        plan=SimpleNamespace(is_active=True),
        status=SubscriptionStatus.ACTIVE,
        current_period_end=now + timedelta(days=1),
        trial_started_at=None,
        trial_ends_at=None,
    )
    assert service.is_entitled(subscription, now)
    subscription.current_period_end = now
    assert not service.is_entitled(subscription, now)
    subscription.plan.is_active = False
    assert not service.is_entitled(subscription, now)


@pytest.mark.parametrize("field", ["price", "trial_days", "monthly_generation_limit"])
def test_plan_rejects_negative_commercial_values(field: str) -> None:
    values = {
        "code": "CUSTOM",
        "name": "Custom",
        "description": "Custom plan",
        "price": 10,
        "currency": "BRL",
        "billing_interval": "month",
        "trial_days": 5,
        "monthly_generation_limit": 10,
        "monthly_input_token_limit": 100,
        "monthly_output_token_limit": 100,
    }
    values[field] = -1
    with pytest.raises(ValidationError):
        PlanCreate(**values)


def test_only_admin_has_billing_management_permission() -> None:
    assert has_permission(Role.ADMIN, Permission.BILLING_MANAGE)
    assert not has_permission(Role.USER, Permission.BILLING_MANAGE)
