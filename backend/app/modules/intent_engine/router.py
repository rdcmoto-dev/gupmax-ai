from typing import Annotated

from fastapi import APIRouter, Depends

from app.modules.users.dependencies import DbSession, get_current_user
from app.modules.users.model import User

from .schemas import IntentAnalysis, IntentAnalyzeRequest
from .service import IntentEngineService

router = APIRouter()
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.post("/analyze", response_model=IntentAnalysis)
async def analyze_intent(
    data: IntentAnalyzeRequest, session: DbSession, user: CurrentUser
) -> IntentAnalysis:
    return await IntentEngineService(session).analyze(user, data)
