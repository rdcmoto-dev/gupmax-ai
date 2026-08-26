from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.projects.service import ProjectService
from app.modules.prompt_chains.model import PromptChain, PromptChainStep
from app.modules.prompt_chains.repository import PromptChainRepository
from app.modules.prompt_chains.schemas import (
    ChainCreate,
    ChainDetail,
    ChainRead,
    ChainUpdate,
    ReorderSteps,
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
        return ChainDetail(**summary.model_dump(), steps=await self.repository.steps(chain.id))

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
