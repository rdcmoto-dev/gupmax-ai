from typing import Annotated

from fastapi import Depends

from app.modules.billing.service import BillingService
from app.modules.users.dependencies import DbSession


def get_billing_service(session: DbSession) -> BillingService:
    return BillingService(session)


Billing = Annotated[BillingService, Depends(get_billing_service)]
