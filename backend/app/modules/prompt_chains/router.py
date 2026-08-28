from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status

from app.modules.prompt_chains.repository import PromptChainRepository
from app.modules.prompt_chains.schemas import (
    ChainCreate,
    ChainDetail,
    ChainPage,
    ChainRead,
    ChainUpdate,
    ReorderSteps,
    StepCompletion,
    StepCreate,
    StepRead,
    StepUpdate,
)
from app.modules.prompt_chains.service import PromptChainService
from app.modules.users.dependencies import DbSession, get_current_user
from app.modules.users.model import User

router = APIRouter()
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.get("", response_model=ChainPage)
async def list_chains(session: DbSession, user: CurrentUser, offset: int = Query(0, ge=0),
                      limit: int = Query(20, ge=1, le=100), include_archived: bool = False) -> ChainPage:
    repository = PromptChainRepository(session)
    service = PromptChainService(session)
    items, total = await repository.list(user.id, offset, limit, include_archived)
    return ChainPage(items=[await service.read(item) for item in items], total=total, offset=offset, limit=limit)


@router.post("", response_model=ChainRead, status_code=status.HTTP_201_CREATED)
async def create_chain(data: ChainCreate, session: DbSession, user: CurrentUser) -> ChainRead:
    service = PromptChainService(session)
    return await service.read(await service.create(user, data))


@router.get("/{chain_id}", response_model=ChainDetail)
async def get_chain(chain_id: UUID, session: DbSession, user: CurrentUser) -> ChainDetail:
    return await PromptChainService(session).detail(chain_id, user)


@router.put("/{chain_id}", response_model=ChainRead)
async def update_chain(chain_id: UUID, data: ChainUpdate, session: DbSession, user: CurrentUser) -> ChainRead:
    service = PromptChainService(session)
    return await service.read(await service.update(chain_id, user, data))


@router.delete("/{chain_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_chain(chain_id: UUID, session: DbSession, user: CurrentUser) -> None:
    service = PromptChainService(session)
    await service.repository.delete(await service.accessible(chain_id, user))


@router.post("/{chain_id}/steps", response_model=StepRead, status_code=status.HTTP_201_CREATED)
async def add_step(chain_id: UUID, data: StepCreate, session: DbSession, user: CurrentUser) -> StepRead:
    return StepRead.model_validate(await PromptChainService(session).add_step(chain_id, user, data))


@router.post("/{chain_id}/execution/start", response_model=ChainDetail)
async def start_execution(chain_id: UUID, session: DbSession, user: CurrentUser) -> ChainDetail:
    return await PromptChainService(session).start_execution(chain_id, user)


@router.put("/{chain_id}/steps/{step_id}/complete", response_model=ChainDetail)
async def complete_step(
    chain_id: UUID,
    step_id: UUID,
    data: StepCompletion,
    session: DbSession,
    user: CurrentUser,
) -> ChainDetail:
    return await PromptChainService(session).complete_step(chain_id, step_id, user, data)


@router.put("/{chain_id}/steps/reorder", status_code=status.HTTP_204_NO_CONTENT)
async def reorder_steps(chain_id: UUID, data: ReorderSteps, session: DbSession, user: CurrentUser) -> None:
    await PromptChainService(session).reorder(chain_id, user, data)


@router.put("/{chain_id}/steps/{step_id}", response_model=StepRead)
async def update_step(chain_id: UUID, step_id: UUID, data: StepUpdate,
                      session: DbSession, user: CurrentUser) -> StepRead:
    return StepRead.model_validate(
        await PromptChainService(session).update_step(chain_id, step_id, user, data)
    )


@router.delete("/{chain_id}/steps/{step_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_step(chain_id: UUID, step_id: UUID, session: DbSession, user: CurrentUser) -> None:
    await PromptChainService(session).delete_step(chain_id, step_id, user)
