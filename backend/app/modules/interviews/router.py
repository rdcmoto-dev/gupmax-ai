from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, status

from app.modules.interviews.schemas import (
    InterviewAnswersRequest,
    InterviewCompleteResponse,
    InterviewCreateRequest,
    InterviewRead,
)
from app.modules.interviews.service import InterviewService
from app.modules.users.dependencies import DbSession, get_current_user
from app.modules.users.model import User

router = APIRouter()
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.post("", response_model=InterviewRead, status_code=status.HTTP_201_CREATED, summary="Inicia uma entrevista")
async def start_interview(data: InterviewCreateRequest, session: DbSession, current_user: CurrentUser) -> InterviewRead:
    return await InterviewService(session).start(current_user, data)


@router.get("/{interview_id}", response_model=InterviewRead, summary="Obtém uma entrevista própria")
async def get_interview(interview_id: UUID, session: DbSession, current_user: CurrentUser) -> InterviewRead:
    return await InterviewService(session).get(interview_id, current_user)


@router.post("/{interview_id}/answers", response_model=InterviewRead, summary="Registra respostas da entrevista")
async def answer_interview(
    interview_id: UUID,
    data: InterviewAnswersRequest,
    session: DbSession,
    current_user: CurrentUser,
) -> InterviewRead:
    return await InterviewService(session).answer(interview_id, current_user, data)


@router.post(
    "/{interview_id}/complete",
    response_model=InterviewCompleteResponse,
    summary="Conclui a entrevista e produz entrada para o Prompt Engine",
)
async def complete_interview(
    interview_id: UUID, session: DbSession, current_user: CurrentUser
) -> InterviewCompleteResponse:
    return await InterviewService(session).complete(interview_id, current_user)
