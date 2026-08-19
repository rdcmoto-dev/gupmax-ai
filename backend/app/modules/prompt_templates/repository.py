from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.prompt_templates.model import PromptTemplate


class PromptTemplateRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(self, **values: object) -> PromptTemplate:
        template = PromptTemplate(**values)
        self.session.add(template)
        await self.session.commit()
        await self.session.refresh(template)
        return template

    async def get(self, template_id: UUID) -> PromptTemplate | None:
        return await self.session.get(PromptTemplate, template_id)

    async def list(self, user_id: UUID, offset: int, limit: int) -> tuple[list[PromptTemplate], int]:
        where = PromptTemplate.user_id == user_id
        total = await self.session.scalar(select(func.count()).select_from(PromptTemplate).where(where)) or 0
        items = list(
            await self.session.scalars(
                select(PromptTemplate)
                .where(where)
                .order_by(PromptTemplate.updated_at.desc())
                .offset(offset)
                .limit(limit)
            )
        )
        return items, total

    async def update(self, template: PromptTemplate, values: dict[str, object]) -> PromptTemplate:
        for key, value in values.items():
            setattr(template, key, value)
        await self.session.commit()
        await self.session.refresh(template)
        return template

    async def delete(self, template: PromptTemplate) -> None:
        await self.session.delete(template)
        await self.session.commit()
