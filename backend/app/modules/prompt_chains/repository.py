from datetime import datetime
from uuid import UUID

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.prompt_chains.model import (
    PromptChain,
    PromptChainStatus,
    PromptChainStep,
    PromptChainStepStatus,
)
from app.modules.prompt_engine.enums import PromptCategory


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

    async def execution_summaries(
        self, chain_ids: list[UUID]
    ) -> dict[
        UUID,
        tuple[int, int, UUID | None, datetime | None, PromptCategory | None],
    ]:
        if not chain_ids:
            return {}
        rows = (await self.session.execute(
            select(
                PromptChainStep.chain_id,
                func.count(PromptChainStep.id),
                func.count(PromptChainStep.id).filter(
                    PromptChainStep.execution_status == PromptChainStepStatus.COMPLETED
                ),
                func.min(PromptChainStep.position).filter(
                    PromptChainStep.execution_status != PromptChainStepStatus.COMPLETED
                ),
                func.max(PromptChainStep.updated_at),
            )
            .where(PromptChainStep.chain_id.in_(chain_ids))
            .group_by(PromptChainStep.chain_id)
        )).all()
        current_positions = {
            (chain_id, position)
            for chain_id, _, _, position, _ in rows
            if position is not None
        }
        current_ids: dict[tuple[UUID, int], UUID] = {}
        categories: dict[UUID, PromptCategory] = {}
        if rows:
            step_rows = (await self.session.execute(
                select(
                    PromptChainStep.chain_id,
                    PromptChainStep.position,
                    PromptChainStep.id,
                    PromptChainStep.category,
                ).where(PromptChainStep.chain_id.in_(chain_ids))
            )).all()
            current_ids = {
                (chain_id, position): step_id
                for chain_id, position, step_id, _ in step_rows
                if (chain_id, position) in current_positions
            }
            categories = {
                chain_id: PromptCategory(category)
                for chain_id, position, _, category in step_rows
                if position == 1
            }
        return {
            chain_id: (
                step_count,
                completed_count,
                current_ids.get((chain_id, current_position)),
                updated_at,
                categories.get(chain_id),
            )
            for chain_id, step_count, completed_count, current_position, updated_at in rows
        }

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

    async def start_execution(
        self, current: PromptChainStep
    ) -> PromptChainStep:
        current.execution_status = PromptChainStepStatus.IN_PROGRESS
        current.started_at = func.now()
        await self.session.commit()
        await self.session.refresh(current)
        return current

    async def complete_and_advance(
        self,
        current: PromptChainStep,
        result: str,
        next_step: PromptChainStep | None,
    ) -> None:
        current.execution_status = PromptChainStepStatus.COMPLETED
        current.result = result
        current.completed_at = func.now()
        if current.started_at is None:
            current.started_at = func.now()
        if next_step is not None:
            next_step.execution_status = PromptChainStepStatus.IN_PROGRESS
            if next_step.started_at is None:
                next_step.started_at = func.now()
        await self.session.commit()

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
