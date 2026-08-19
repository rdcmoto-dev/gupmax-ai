from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.modules.smart_profile.schemas import SmartProfileRead, SmartProfileWrite
from app.modules.smart_profile.service import SmartProfileService
from app.modules.users.dependencies import DbSession, get_current_user
from app.modules.users.model import User

router = APIRouter()
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get("/prompt-preferences", response_model=SmartProfileRead)
async def get_preferences(session: DbSession, current_user: CurrentUser) -> SmartProfileRead:
    return await SmartProfileService(session).get(current_user)


@router.put("/prompt-preferences", response_model=SmartProfileRead)
async def save_preferences(
    data: SmartProfileWrite, session: DbSession, current_user: CurrentUser
) -> SmartProfileRead:
    return await SmartProfileService(session).save(current_user, data)


@router.delete("/prompt-preferences", status_code=status.HTTP_204_NO_CONTENT)
async def delete_preferences(session: DbSession, current_user: CurrentUser) -> None:
    await SmartProfileService(session).delete(current_user)
