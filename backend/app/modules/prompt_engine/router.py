from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status

from app.modules.ai_gateway.dependencies import AIGateway
from app.modules.prompt_engine.enums import PromptCategory, PromptMode
from app.modules.prompt_engine.repository import PromptRepository
from app.modules.prompt_engine.schemas import (
    PromptGenerateRequest,
    PromptGenerateResponse,
    PromptPage,
    PromptRead,
    PromptUpdateRequest,
)
from app.modules.prompt_engine.service import PromptService
from app.modules.users.dependencies import DbSession, get_current_user
from app.modules.users.model import User
from app.modules.users.roles import Role

router = APIRouter()
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.post(
    "/generate",
    response_model=PromptGenerateResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Gera e salva um prompt estruturado",
    responses={401: {"description": "Não autenticado"}, 503: {"description": "AI Gateway indisponível"}},
)
async def generate_prompt(
    data: PromptGenerateRequest, session: DbSession, current_user: CurrentUser, gateway: AIGateway
) -> PromptGenerateResponse:
    return await PromptService(session, gateway).generate(current_user, data)


@router.get("", response_model=PromptPage, summary="Lista o histórico de prompts acessível")
async def list_prompts(
    session: DbSession,
    current_user: CurrentUser,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
    category: PromptCategory | None = None,
    language: str | None = Query(default=None, min_length=2, max_length=20),
    mode: PromptMode | None = None,
    created_from: datetime | None = None,
    created_to: datetime | None = None,
    order: Literal["asc", "desc"] = "desc",
) -> PromptPage:
    items, total = await PromptRepository(session).list(
        user_id=None if current_user.role == Role.ADMIN else current_user.id,
        offset=offset,
        limit=limit,
        category=category,
        language=language,
        mode=mode,
        created_from=created_from,
        created_to=created_to,
        descending=order == "desc",
    )
    return PromptPage(items=items, total=total, offset=offset, limit=limit)


@router.get("/{prompt_id}", response_model=PromptRead, summary="Obtém um prompt")
async def get_prompt(prompt_id: UUID, session: DbSession, current_user: CurrentUser) -> PromptRead:
    return await PromptService(session).accessible(prompt_id, current_user)


@router.put("/{prompt_id}", response_model=PromptRead, summary="Atualiza um prompt")
async def update_prompt(
    prompt_id: UUID, data: PromptUpdateRequest, session: DbSession, current_user: CurrentUser
) -> PromptRead:
    return await PromptService(session).update(prompt_id, current_user, data)


@router.delete("/{prompt_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Remove um prompt")
async def delete_prompt(prompt_id: UUID, session: DbSession, current_user: CurrentUser) -> None:
    await PromptService(session).delete(prompt_id, current_user)
