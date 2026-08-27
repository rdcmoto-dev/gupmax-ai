from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.modules.users.dependencies import DbSession, get_current_user
from app.modules.users.model import User

from .schemas import CreateChainFromPlan, CreatedPlanChain, ExpertPlan, ExpertPlanRequest
from .service import ExpertPlannerService

router = APIRouter()
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.post("/plan", response_model=ExpertPlan)
async def create_plan(
    data: ExpertPlanRequest, session: DbSession, user: CurrentUser
) -> ExpertPlan:
    return await ExpertPlannerService(session).plan(user, data)


@router.post("/chains", response_model=CreatedPlanChain, status_code=status.HTTP_201_CREATED)
async def create_chain(
    data: CreateChainFromPlan, session: DbSession, user: CurrentUser
) -> CreatedPlanChain:
    chain = await ExpertPlannerService(session).create_chain(user, data)
    return CreatedPlanChain(chain=chain)
