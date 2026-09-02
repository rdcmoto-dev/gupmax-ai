from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.projects.model import Project
from app.modules.projects.service import ProjectService
from app.modules.prompt_chains.model import PromptChain, PromptChainStep, PromptChainStepStatus
from app.modules.prompt_chains.repository import PromptChainRepository
from app.modules.prompt_chains.schemas import (
    ChainCreate,
    ChainDetail,
    ChainRead,
    ChainUpdate,
    ReorderSteps,
    StepCompletion,
    StepCreate,
    StepUpdate,
)
from app.modules.prompt_templates.repository import PromptTemplateRepository
from app.modules.users.model import User

MAX_CHAIN_STEPS = 20


class PromptChainService:
    def __init__(self, session: AsyncSession) -> None:
        self.repository = PromptChainRepository(session)
        self.projects = ProjectService(session)
        self.templates = PromptTemplateRepository(session)

    async def accessible(self, chain_id: UUID, user: User) -> PromptChain:
        chain = await self.repository.get(chain_id)
        if chain is None or chain.user_id != user.id:
            raise HTTPException(status_code=404, detail="Prompt chain not found")
        return chain

    async def save_as_project(self, chain_id: UUID, user: User) -> Project:
        chain = await self.repository.get_for_update(chain_id)
        if chain is None or chain.user_id != user.id:
            raise HTTPException(status_code=404, detail="Prompt chain not found")
        if chain.project_id is not None:
            return await self.projects.accessible(chain.project_id, user)
        return await self.repository.attach_new_project(
            chain,
            {
                "user_id": user.id,
                "name": chain.name[:160],
                "description": chain.description,
                "context": chain.description,
            },
        )

    async def accessible_step(self, chain_id: UUID, step_id: UUID, user: User) -> PromptChainStep:
        await self.accessible(chain_id, user)
        step = await self.repository.step(step_id)
        if step is None or step.chain_id != chain_id:
            raise HTTPException(status_code=404, detail="Prompt chain step not found")
        return step

    async def create(self, user: User, data: ChainCreate) -> PromptChain:
        if data.project_id is not None:
            await self.projects.accessible(data.project_id, user)
        return await self.repository.create(user_id=user.id, **data.model_dump())

    async def read(self, chain: PromptChain) -> ChainRead:
        steps = await self.repository.steps(chain.id)
        return ChainRead.model_validate(chain).model_copy(update={"step_count": len(steps)})

    async def detail(self, chain_id: UUID, user: User) -> ChainDetail:
        chain = await self.accessible(chain_id, user)
        summary = await self.read(chain)
        steps = await self.repository.steps(chain.id)
        completed = sum(step.execution_status == PromptChainStepStatus.COMPLETED for step in steps)
        current = next(
            (step for step in steps if step.execution_status != PromptChainStepStatus.COMPLETED),
            None,
        )
        return ChainDetail(
            **summary.model_dump(
                exclude={
                    "completed_step_count",
                    "current_step_id",
                    "execution_completed",
                }
            ),
            steps=steps,
            completed_step_count=completed,
            current_step_id=current.id if current else None,
            execution_completed=bool(steps) and completed == len(steps),
        )

    async def start_execution(self, chain_id: UUID, user: User) -> ChainDetail:
        chain = await self.accessible(chain_id, user)
        steps = await self.repository.steps(chain.id)
        current = next(
            (step for step in steps if step.execution_status != PromptChainStepStatus.COMPLETED),
            None,
        )
        if current is None:
            if not steps:
                raise HTTPException(status_code=422, detail="Chain has no steps")
            return await self.detail(chain_id, user)
        if current.execution_status == PromptChainStepStatus.PENDING:
            await self.repository.start_execution(current)
        return await self.detail(chain_id, user)

    async def complete_step(
        self, chain_id: UUID, step_id: UUID, user: User, data: StepCompletion
    ) -> ChainDetail:
        chain = await self.accessible(chain_id, user)
        step = await self.accessible_step(chain_id, step_id, user)
        steps = await self.repository.steps(chain.id)
        current_index = next(
            (
                index
                for index, item in enumerate(steps)
                if item.execution_status != PromptChainStepStatus.COMPLETED
            ),
            None,
        )
        if current_index is None or steps[current_index].id != step.id:
            raise HTTPException(status_code=409, detail="Only the current step can be completed")
        if step.execution_status != PromptChainStepStatus.IN_PROGRESS:
            raise HTTPException(status_code=409, detail="Start the chain before completing a step")
        next_step = steps[current_index + 1] if current_index + 1 < len(steps) else None
        await self.repository.complete_and_advance(step, data.result, next_step)
        return await self.detail(chain_id, user)

    async def update(self, chain_id: UUID, user: User, data: ChainUpdate) -> PromptChain:
        values = data.model_dump(exclude_unset=True)
        if values.get("project_id") is not None:
            await self.projects.accessible(values["project_id"], user)
        return await self.repository.update(await self.accessible(chain_id, user), values)

    async def add_step(self, chain_id: UUID, user: User, data: StepCreate) -> PromptChainStep:
        chain = await self.accessible(chain_id, user)
        steps = await self.repository.steps(chain.id)
        if len(steps) >= MAX_CHAIN_STEPS:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail="Maximum 20 steps")
        await self._template(data.template_id, user)
        return await self.repository.add_step(
            chain_id=chain.id, position=len(steps) + 1, **data.model_dump()
        )

    async def update_step(
        self, chain_id: UUID, step_id: UUID, user: User, data: StepUpdate
    ) -> PromptChainStep:
        values = data.model_dump(exclude_unset=True)
        if "template_id" in values:
            await self._template(values["template_id"], user)
        return await self.repository.update_step(
            await self.accessible_step(chain_id, step_id, user), values
        )

    async def delete_step(self, chain_id: UUID, step_id: UUID, user: User) -> None:
        await self.repository.delete_step(await self.accessible_step(chain_id, step_id, user))

    async def reorder(self, chain_id: UUID, user: User, data: ReorderSteps) -> None:
        chain = await self.accessible(chain_id, user)
        current = await self.repository.steps(chain.id)
        if len(data.step_ids) != len(current) or set(data.step_ids) != {step.id for step in current}:
            raise HTTPException(status_code=422, detail="Step order must contain every step exactly once")
        await self.repository.reorder(chain.id, data.step_ids)

    async def _template(self, template_id: UUID | None, user: User) -> None:
        if template_id is None:
            return
        template = await self.templates.get(template_id)
        if template is None or template.user_id != user.id:
            raise HTTPException(status_code=404, detail="Template not found")
