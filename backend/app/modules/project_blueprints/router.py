from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status

from app.modules.project_blueprints.schemas import (
    BlueprintCreate,
    BlueprintDetail,
    BlueprintPage,
    BlueprintRead,
    BlueprintUpdate,
    BlueprintUse,
)
from app.modules.project_blueprints.service import BlueprintService
from app.modules.projects.schemas import ProjectRead
from app.modules.projects.service import ProjectService
from app.modules.users.dependencies import DbSession, get_current_user
from app.modules.users.model import User

router = APIRouter()
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get("", response_model=BlueprintPage)
async def list_blueprints(
    session: DbSession, current_user: CurrentUser, offset: int = Query(0, ge=0), limit: int = Query(20, ge=1, le=100)
) -> BlueprintPage:
    return await BlueprintService(session).list(current_user, offset, limit)


@router.post("", response_model=BlueprintDetail, status_code=status.HTTP_201_CREATED)
async def create_blueprint(data: BlueprintCreate, session: DbSession, current_user: CurrentUser) -> BlueprintDetail:
    return BlueprintDetail.model_validate(await BlueprintService(session).create(current_user, data))


@router.get("/{blueprint_id}", response_model=BlueprintDetail)
async def get_blueprint(blueprint_id: UUID, session: DbSession, current_user: CurrentUser) -> BlueprintDetail:
    return BlueprintDetail.model_validate(await BlueprintService(session).accessible(blueprint_id, current_user))


@router.put("/{blueprint_id}", response_model=BlueprintRead)
async def update_blueprint(
    blueprint_id: UUID, data: BlueprintUpdate, session: DbSession, current_user: CurrentUser
) -> BlueprintRead:
    return BlueprintRead.model_validate(await BlueprintService(session).update(blueprint_id, current_user, data))


@router.delete("/{blueprint_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_blueprint(blueprint_id: UUID, session: DbSession, current_user: CurrentUser) -> None:
    await BlueprintService(session).delete(blueprint_id, current_user)


@router.post("/{blueprint_id}/projects", response_model=ProjectRead, status_code=status.HTTP_201_CREATED)
async def use_blueprint(
    blueprint_id: UUID, data: BlueprintUse, session: DbSession, current_user: CurrentUser
) -> ProjectRead:
    project = await BlueprintService(session).use(blueprint_id, current_user, data)
    return await ProjectService(session).read(project)
