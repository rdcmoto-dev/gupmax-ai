from decimal import Decimal
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app.modules.credits.defaults import INITIAL_PACKAGES
from app.modules.credits.schemas import AdjustmentRequest, PackageCreate
from app.modules.credits.service import CreditCostService


def test_credit_cost_rounds_up_and_honors_minimum() -> None:
    rule = SimpleNamespace(
        base_credit_cost=1,
        input_token_rate=Decimal("0.001"),
        output_token_rate=Decimal("0.002"),
        minimum_credit_cost=3,
    )
    assert CreditCostService.calculate(rule, 10, 5) == 3
    rule.minimum_credit_cost = 0
    assert CreditCostService.calculate(rule, 1_000, 500) == 3


def test_initial_credit_packages_are_ordered_and_positive() -> None:
    assert [package.code for package in INITIAL_PACKAGES] == [
        "CREDITS_500",
        "CREDITS_1500",
        "CREDITS_5000",
        "CREDITS_10000",
    ]
    assert all(package.credits > 0 and package.price >= 0 for package in INITIAL_PACKAGES)
    assert [package.sort_order for package in INITIAL_PACKAGES] == sorted(
        package.sort_order for package in INITIAL_PACKAGES
    )


@pytest.mark.parametrize("field", ["credits", "price", "bonus_credits"])
def test_package_rejects_negative_values(field: str) -> None:
    data = {
        "code": "CREDITS_TEST",
        "name": "Test",
        "credits": 100,
        "price": "10.00",
        "currency": "BRL",
        "bonus_credits": 0,
    }
    data[field] = -1
    with pytest.raises(ValidationError):
        PackageCreate(**data)


def test_adjustment_requires_nontrivial_reason_and_nonzero_is_service_validated() -> None:
    with pytest.raises(ValidationError):
        AdjustmentRequest(
            user_id="10000000-0000-0000-0000-000000000001",
            amount=10,
            reason="x",
            idempotency_key="12345678",
        )
