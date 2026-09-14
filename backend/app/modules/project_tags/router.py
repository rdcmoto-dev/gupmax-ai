from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.project_tags.model import ProjectTag, project_tag_links
from app.modules.project_tags.schemas import TagInput, TagRead
from app.modules.projects.model import Project
from app.modules.users.dependencies import DbSession, get_current_user
from app.modules.users.model import User

router = APIRouter()


async def lock_owner(session: AsyncSession, user: User) -> None:
    await session.execute(select(User.id).where(User.id == user.id).with_for_update())

CurrentUser = Annotated[User, Depends(get_current_user)]


async def tag(session: AsyncSession, id: UUID, user: User) -> ProjectTag:
    r = await session.scalar(select(ProjectTag).where(ProjectTag.id == id, ProjectTag.user_id == user.id))
    if r is None:
        raise HTTPException(404, "Tag not found")
    return r


async def project(session: AsyncSession, id: UUID, user: User) -> Project:
    r = await session.scalar(select(Project).where(Project.id == id, Project.user_id == user.id))
    if r is None:
        raise HTTPException(404, "Project not found")
    return r


@router.get("", response_model=list[TagRead])
async def list_tags(session: DbSession, current_user: CurrentUser):
    return list(
        (
            await session.scalars(
                select(ProjectTag).where(ProjectTag.user_id == current_user.id).order_by(ProjectTag.name)
            )
        ).all()
    )


@router.post("", response_model=TagRead, status_code=201)
async def create_tag(data: TagInput, session: DbSession, current_user: CurrentUser):
    await lock_owner(session, current_user)
    if await session.scalar(
        select(ProjectTag).where(
            ProjectTag.user_id == current_user.id, func.lower(ProjectTag.name) == data.name.lower()
        )
    ):
        raise HTTPException(409, "Já existe uma Tag com esse nome.")
    if (
        await session.scalar(select(func.count()).select_from(ProjectTag).where(ProjectTag.user_id == current_user.id))
    ) >= 50:
        raise HTTPException(409, "Máximo de 50 etiquetas.")
    r = ProjectTag(user_id=current_user.id, name=data.name)
    session.add(r)
    await session.commit()
    await session.refresh(r)
    return r


@router.put("/{tag_id}", response_model=TagRead)
async def update_tag(tag_id: UUID, data: TagInput, session: DbSession, current_user: CurrentUser):
    await lock_owner(session, current_user)
    r = await tag(session, tag_id, current_user)
    if await session.scalar(select(ProjectTag.id).where(
        ProjectTag.user_id == current_user.id,
        func.lower(ProjectTag.name) == data.name.lower(), ProjectTag.id != tag_id,
    )):
        raise HTTPException(409, "Já existe uma Tag com esse nome.")
    r.name = data.name
    await session.commit()
    await session.refresh(r)
    return r


@router.delete("/{tag_id}", status_code=204)
async def delete_tag(tag_id: UUID, session: DbSession, current_user: CurrentUser):
    await lock_owner(session, current_user)
    record = await tag(session, tag_id, current_user)
    await session.execute(project_tag_links.delete().where(project_tag_links.c.tag_id == tag_id))
    await session.delete(record)
    await session.commit()


@router.put("/projects/{project_id}/{tag_id}", status_code=204)
async def attach(project_id: UUID, tag_id: UUID, session: DbSession, current_user: CurrentUser):
    await lock_owner(session, current_user)
    p = await project(session, project_id, current_user)
    t = await tag(session, tag_id, current_user)
    if await session.scalar(select(project_tag_links.c.tag_id).where(
        project_tag_links.c.project_id == p.id, project_tag_links.c.tag_id == t.id,
    )):
        return
    if (
        await session.scalar(
            select(func.count()).select_from(project_tag_links).where(project_tag_links.c.project_id == p.id)
        )
    ) >= 10:
        raise HTTPException(409, "Máximo de 10 etiquetas por projeto.")
    await session.execute(project_tag_links.insert().values(project_id=p.id, tag_id=t.id))
    await session.commit()


@router.delete("/projects/{project_id}/{tag_id}", status_code=204)
async def detach(project_id: UUID, tag_id: UUID, session: DbSession, current_user: CurrentUser):
    await lock_owner(session, current_user)
    p = await project(session, project_id, current_user)
    await tag(session, tag_id, current_user)
    await session.execute(
        project_tag_links.delete().where(project_tag_links.c.project_id == p.id, project_tag_links.c.tag_id == tag_id)
    )
    await session.commit()
