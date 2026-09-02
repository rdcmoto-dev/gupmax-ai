from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status

from app.modules.projects.repository import ProjectRepository
from app.modules.projects.schemas import (
    ProjectCreate,
    ProjectDetail,
    ProjectLibraryPage,
    ProjectPage,
    ProjectRead,
    ProjectUpdate,
)
from app.modules.projects.service import ProjectService
from app.modules.users.dependencies import DbSession, get_current_user
from app.modules.users.model import User

router = APIRouter()
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get("", response_model=ProjectPage)
async def list_projects(
    session: DbSession,
    current_user: CurrentUser,
    offset: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    include_archived: bool = False,
) -> ProjectPage:
    repository = ProjectRepository(session)
    items, total = await repository.list(current_user.id, offset, limit, include_archived)
    counts = await repository.counts_many([item.id for item in items])
    reads = [
        ProjectRead.model_validate(item).model_copy(
            update={
                "prompt_count": counts[item.id][0],
                "template_count": counts[item.id][1],
            }
        )
        for item in items
    ]
    return ProjectPage(items=reads, total=total, offset=offset, limit=limit)


@router.post("", response_model=ProjectRead, status_code=status.HTTP_201_CREATED)
async def create_project(data: ProjectCreate, session: DbSession, current_user: CurrentUser) -> ProjectRead:
    service = ProjectService(session)
    return await service.read(await service.create(current_user, data))


@router.get("/{project_id}", response_model=ProjectDetail)
async def get_project(project_id: UUID, session: DbSession, current_user: CurrentUser) -> ProjectDetail:
    return await ProjectService(session).detail(project_id, current_user)


@router.get("/{project_id}/library", response_model=ProjectLibraryPage)
async def get_project_library(
    project_id: UUID,
    session: DbSession,
    current_user: CurrentUser,
    offset: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=50),
) -> ProjectLibraryPage:
    return await ProjectService(session).library(project_id, current_user, offset, limit)


@router.put("/{project_id}", response_model=ProjectRead)
async def update_project(
    project_id: UUID, data: ProjectUpdate, session: DbSession, current_user: CurrentUser
) -> ProjectRead:
    service = ProjectService(session)
    return await service.read(await service.update(project_id, current_user, data))


@router.delete("/{project_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_project(project_id: UUID, session: DbSession, current_user: CurrentUser) -> None:
    await ProjectService(session).delete(project_id, current_user)


@router.put("/{project_id}/prompts/{prompt_id}", status_code=status.HTTP_204_NO_CONTENT)
async def assign_prompt(project_id: UUID, prompt_id: UUID, session: DbSession, current_user: CurrentUser) -> None:
    await ProjectService(session).assign_prompt(project_id, prompt_id, current_user)


@router.delete("/{project_id}/prompts/{prompt_id}", status_code=status.HTTP_204_NO_CONTENT)
async def unassign_prompt(project_id: UUID, prompt_id: UUID, session: DbSession, current_user: CurrentUser) -> None:
    await ProjectService(session).unassign_prompt(project_id, prompt_id, current_user)


@router.put("/{project_id}/templates/{template_id}", status_code=status.HTTP_204_NO_CONTENT)
async def assign_template(project_id: UUID, template_id: UUID, session: DbSession, current_user: CurrentUser) -> None:
    await ProjectService(session).assign_template(project_id, template_id, current_user)


@router.delete("/{project_id}/templates/{template_id}", status_code=status.HTTP_204_NO_CONTENT)
async def unassign_template(project_id: UUID, template_id: UUID, session: DbSession, current_user: CurrentUser) -> None:
    await ProjectService(session).unassign_template(project_id, template_id, current_user)
