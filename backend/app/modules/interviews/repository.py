from datetime import datetime
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.modules.interviews.enums import InterviewStatus
from app.modules.interviews.model import InterviewAnswer, InterviewSession


class InterviewRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(self, **values: object) -> InterviewSession:
        interview = InterviewSession(**values)
        self.session.add(interview)
        await self.session.commit()
        return await self.get_by_id(interview.id)  # type: ignore[return-value]

    async def get_by_id(self, interview_id: UUID) -> InterviewSession | None:
        return await self.session.scalar(
            select(InterviewSession)
            .options(selectinload(InterviewSession.answers))
            .where(InterviewSession.id == interview_id)
            .execution_options(populate_existing=True)
        )

    async def upsert_answers(self, interview: InterviewSession, values: dict[str, Any]) -> InterviewSession:
        existing = {answer.question_key: answer for answer in interview.answers}
        for key, value in values.items():
            answer = existing.get(key)
            if answer is None:
                self.session.add(InterviewAnswer(interview_id=interview.id, question_key=key, value=value))
            else:
                answer.value = value
        interview.updated_at = datetime.now().astimezone()
        await self.session.commit()
        return await self.get_by_id(interview.id)  # type: ignore[return-value]

    async def update_status(self, interview: InterviewSession, status: InterviewStatus) -> InterviewSession:
        interview.status = status
        interview.updated_at = datetime.now().astimezone()
        await self.session.commit()
        return await self.get_by_id(interview.id)  # type: ignore[return-value]

    async def complete(self, interview: InterviewSession, payload: dict[str, Any], now: datetime) -> InterviewSession:
        interview.status = InterviewStatus.COMPLETED
        interview.structured_prompt = payload
        interview.completed_at = now
        interview.updated_at = now
        await self.session.commit()
        return await self.get_by_id(interview.id)  # type: ignore[return-value]
