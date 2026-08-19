from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status

from app.modules.prompt_templates.repository import PromptTemplateRepository
from app.modules.prompt_templates.schemas import (
    TemplateCreate,
    TemplateFromPrompt,
    TemplatePage,
    TemplateRead,
    TemplateUpdate,
)
from app.modules.prompt_templates.service import PromptTemplateService
from app.modules.users.dependencies import DbSession, get_current_user
from app.modules.users.model import User

router = APIRouter()
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get("", response_model=TemplatePage)
async def list_templates(
    session: DbSession,
    current_user: CurrentUser,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
) -> TemplatePage:
    items, total = await PromptTemplateRepository(session).list(current_user.id, offset, limit)
    return TemplatePage(items=items, total=total, offset=offset, limit=limit)


@router.post("", response_model=TemplateRead, status_code=status.HTTP_201_CREATED)
async def create_template(data: TemplateCreate, session: DbSession, current_user: CurrentUser) -> TemplateRead:
    return await PromptTemplateService(session).create(current_user, data)


@router.get("/{template_id}", response_model=TemplateRead)
async def get_template(template_id: UUID, session: DbSession, current_user: CurrentUser) -> TemplateRead:
    return await PromptTemplateService(session).accessible(template_id, current_user)


@router.put("/{template_id}", response_model=TemplateRead)
async def update_template(
    template_id: UUID, data: TemplateUpdate, session: DbSession, current_user: CurrentUser
) -> TemplateRead:
    return await PromptTemplateService(session).update(template_id, current_user, data)


@router.delete("/{template_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_template(template_id: UUID, session: DbSession, current_user: CurrentUser) -> None:
    await PromptTemplateService(session).delete(template_id, current_user)


@router.post("/from-prompt/{prompt_id}", response_model=TemplateRead, status_code=status.HTTP_201_CREATED)
async def template_from_prompt(
    prompt_id: UUID, data: TemplateFromPrompt, session: DbSession, current_user: CurrentUser
) -> TemplateRead:
    return await PromptTemplateService(session).from_prompt(prompt_id, current_user, data)
