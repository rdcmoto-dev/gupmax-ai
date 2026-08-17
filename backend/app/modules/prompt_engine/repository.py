from datetime import datetime
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.prompt_engine.enums import PromptCategory, PromptMode
from app.modules.prompt_engine.model import Prompt


class PromptRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(self, **values: object) -> Prompt:
        prompt = Prompt(**values)
        self.session.add(prompt)
        await self.session.commit()
        await self.session.refresh(prompt)
        return prompt

    async def get_by_id(self, prompt_id: UUID) -> Prompt | None:
        return await self.session.get(Prompt, prompt_id)

    async def get_by_idempotency_key(self, user_id: UUID, key: str) -> Prompt | None:
        return await self.session.scalar(select(Prompt).where(Prompt.user_id == user_id, Prompt.idempotency_key == key))

    async def list(
        self,
        *,
        user_id: UUID | None,
        offset: int,
        limit: int,
        category: PromptCategory | None,
        language: str | None,
        mode: PromptMode | None,
        created_from: datetime | None,
        created_to: datetime | None,
        descending: bool,
    ) -> tuple[list[Prompt], int]:
        filters = []
        if user_id is not None:
            filters.append(Prompt.user_id == user_id)
        if category is not None:
            filters.append(Prompt.category == category)
        if language is not None:
            filters.append(Prompt.language == language)
        if mode is not None:
            filters.append(Prompt.mode == mode)
        if created_from is not None:
            filters.append(Prompt.created_at >= created_from)
        if created_to is not None:
            filters.append(Prompt.created_at <= created_to)
        order = Prompt.created_at.desc() if descending else Prompt.created_at.asc()
        items = list(
            (
                await self.session.scalars(select(Prompt).where(*filters).order_by(order).offset(offset).limit(limit))
            ).all()
        )
        total = await self.session.scalar(select(func.count()).select_from(Prompt).where(*filters))
        return items, total or 0

    async def update(self, prompt: Prompt, **values: object) -> Prompt:
        for field, value in values.items():
            if value is not None:
                setattr(prompt, field, value)
        await self.session.commit()
        await self.session.refresh(prompt)
        return prompt

    async def delete(self, prompt: Prompt) -> None:
        await self.session.delete(prompt)
        await self.session.commit()
