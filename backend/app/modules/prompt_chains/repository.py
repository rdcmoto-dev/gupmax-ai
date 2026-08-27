from uuid import UUID

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.prompt_chains.model import PromptChain, PromptChainStatus, PromptChainStep


class PromptChainRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(self, **values: object) -> PromptChain:
        chain = PromptChain(**values)
        self.session.add(chain)
        await self.session.commit()
        await self.session.refresh(chain)
        return chain

    async def create_with_steps(
        self, *, chain_values: dict[str, object], steps: list[dict[str, object]]
    ) -> PromptChain:
        chain = PromptChain(**chain_values)
        self.session.add(chain)
        await self.session.flush()
        self.session.add_all(
            PromptChainStep(chain_id=chain.id, position=index, **values)
            for index, values in enumerate(steps, 1)
        )
        await self.session.commit()
        await self.session.refresh(chain)
        return chain

    async def get(self, chain_id: UUID) -> PromptChain | None:
        return await self.session.get(PromptChain, chain_id)

    async def list(self, user_id: UUID, offset: int, limit: int, include_archived: bool):
        filters = [PromptChain.user_id == user_id]
        if not include_archived:
            filters.append(PromptChain.status == PromptChainStatus.ACTIVE)
        query = select(PromptChain).where(*filters).order_by(PromptChain.updated_at.desc())
        items = list((await self.session.scalars(query.offset(offset).limit(limit))).all())
        total = await self.session.scalar(select(func.count()).select_from(PromptChain).where(*filters))
        return items, total or 0

    async def update(self, chain: PromptChain, values: dict[str, object]) -> PromptChain:
        for key, value in values.items():
            setattr(chain, key, value)
        await self.session.commit()
        await self.session.refresh(chain)
        return chain

    async def delete(self, chain: PromptChain) -> None:
        await self.session.delete(chain)
        await self.session.commit()

    async def steps(self, chain_id: UUID) -> list[PromptChainStep]:
        return list((await self.session.scalars(
            select(PromptChainStep).where(PromptChainStep.chain_id == chain_id).order_by(PromptChainStep.position)
        )).all())

    async def step(self, step_id: UUID) -> PromptChainStep | None:
        return await self.session.get(PromptChainStep, step_id)

    async def add_step(self, **values: object) -> PromptChainStep:
        step = PromptChainStep(**values)
        self.session.add(step)
        await self.session.commit()
        await self.session.refresh(step)
        return step

    async def update_step(self, step: PromptChainStep, values: dict[str, object]) -> PromptChainStep:
        for key, value in values.items():
            setattr(step, key, value)
        await self.session.commit()
        await self.session.refresh(step)
        return step

    async def delete_step(self, step: PromptChainStep) -> None:
        chain_id, position = step.chain_id, step.position
        await self.session.delete(step)
        await self.session.flush()
        await self.session.execute(
            update(PromptChainStep)
            .where(PromptChainStep.chain_id == chain_id, PromptChainStep.position > position)
            .values(position=PromptChainStep.position - 1)
        )
        await self.session.commit()

    async def reorder(self, chain_id: UUID, step_ids: list[UUID]) -> None:
        # Move to temporary positions to preserve the unique constraint.
        for index, step_id in enumerate(step_ids, 1):
            await self.session.execute(
                update(PromptChainStep).where(PromptChainStep.id == step_id).values(position=-index)
            )
        await self.session.flush()
        for index, step_id in enumerate(step_ids, 1):
            await self.session.execute(
                update(PromptChainStep).where(PromptChainStep.id == step_id).values(position=index)
            )
        await self.session.commit()
