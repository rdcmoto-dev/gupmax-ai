from typing import Annotated

from fastapi import Depends

from app.modules.credits.service import CreditService
from app.modules.users.dependencies import DbSession


def get_credit_service(session: DbSession) -> CreditService:
    return CreditService(session)


Credits = Annotated[CreditService, Depends(get_credit_service)]
