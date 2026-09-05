from uuid import UUID

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.projects.model import Project, ProjectStatus
from app.modules.prompt_chains.model import PromptChain, PromptChainStep
from app.modules.prompt_engine.model import Prompt
from app.modules.prompt_templates.model import PromptTemplate


class ProjectRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(self, **values: object) -> Project:
        project = Project(**values)
        self.session.add(project)
        await self.session.commit()
        await self.session.refresh(project)
        return project

    async def get(self, project_id: UUID) -> Project | None:
        return await self.session.get(Project, project_id)

    async def list(self, user_id: UUID, offset: int, limit: int, include_archived: bool) -> tuple[list[Project], int]:
        filters = [Project.user_id == user_id]
        if not include_archived:
            filters.append(Project.status == ProjectStatus.ACTIVE)
        items = list(
            (
                await self.session.scalars(
                    select(Project).where(*filters).order_by(Project.updated_at.desc()).offset(offset).limit(limit)
                )
            ).all()
        )
        total = await self.session.scalar(select(func.count()).select_from(Project).where(*filters))
        return items, total or 0

    async def counts(self, project_id: UUID) -> tuple[int, int]:
        prompts = await self.session.scalar(
            select(func.count()).select_from(Prompt).where(Prompt.project_id == project_id)
        )
        templates = await self.session.scalar(
            select(func.count()).select_from(PromptTemplate).where(PromptTemplate.project_id == project_id)
        )
        return prompts or 0, templates or 0

    async def counts_many(self, project_ids: list[UUID]) -> dict[UUID, tuple[int, int]]:
        if not project_ids:
            return {}
        prompt_rows = (
            await self.session.execute(
                select(Prompt.project_id, func.count(Prompt.id))
                .where(Prompt.project_id.in_(project_ids))
                .group_by(Prompt.project_id)
            )
        ).all()
        template_rows = (
            await self.session.execute(
                select(PromptTemplate.project_id, func.count(PromptTemplate.id))
                .where(PromptTemplate.project_id.in_(project_ids))
                .group_by(PromptTemplate.project_id)
            )
        ).all()
        prompts = {project_id: count for project_id, count in prompt_rows}
        templates = {project_id: count for project_id, count in template_rows}
        return {
            project_id: (
                prompts.get(project_id, 0),
                templates.get(project_id, 0),
            )
            for project_id in project_ids
        }

    async def contents(self, project_id: UUID) -> tuple[list[Prompt], list[PromptTemplate]]:
        prompts = list(
            (
                await self.session.scalars(
                    select(Prompt).where(Prompt.project_id == project_id).order_by(Prompt.updated_at.desc())
                )
            ).all()
        )
        templates = list(
            (
                await self.session.scalars(
                    select(PromptTemplate)
                    .where(PromptTemplate.project_id == project_id)
                    .order_by(PromptTemplate.updated_at.desc())
                )
            ).all()
        )
        return prompts, templates

    async def library_prompts(self, project_id: UUID, offset: int, limit: int) -> tuple[list[tuple[Prompt, int]], int]:
        root_key = func.coalesce(Prompt.root_prompt_id, Prompt.id)
        roots = (
            select(
                root_key.label("root_id"),
                func.count(Prompt.id).label("version_count"),
                func.max(Prompt.updated_at).label("recent_at"),
            )
            .where(Prompt.project_id == project_id)
            .group_by(root_key)
            .subquery()
        )
        representative = (
            func.row_number()
            .over(
                partition_by=root_key,
                order_by=(Prompt.version_number.desc(), Prompt.updated_at.desc(), Prompt.id.asc()),
            )
            .label("row_number")
        )
        ranked = (
            select(Prompt.id.label("prompt_id"), root_key.label("root_id"), representative)
            .where(Prompt.project_id == project_id)
            .subquery()
        )
        query = (
            select(Prompt, roots.c.version_count)
            .join(ranked, ranked.c.prompt_id == Prompt.id)
            .join(roots, roots.c.root_id == ranked.c.root_id)
            .where(ranked.c.row_number == 1)
            .order_by(roots.c.recent_at.desc(), roots.c.root_id.asc())
            .offset(offset)
            .limit(limit)
        )
        rows = list((await self.session.execute(query)).all())
        total = await self.session.scalar(select(func.count()).select_from(roots))
        return rows, total or 0

    async def export_prompts(self, project_id: UUID, user_id: UUID, limit: int) -> list[Prompt]:
        """Return every project prompt in deterministic version order.

        Export has its own bounded query so it cannot accidentally inherit the
        Project Library pagination contract.
        """
        return list(
            (
                await self.session.scalars(
                    select(Prompt)
                    .where(Prompt.project_id == project_id, Prompt.user_id == user_id)
                    .order_by(
                        func.coalesce(Prompt.root_prompt_id, Prompt.id),
                        Prompt.version_number,
                        Prompt.created_at,
                        Prompt.id,
                    )
                    .limit(limit + 1)
                )
            ).all()
        )

    async def project_chains(
        self, project_id: UUID, user_id: UUID | None = None
    ) -> list[tuple[PromptChain, list[PromptChainStep]]]:
        filters = [PromptChain.project_id == project_id]
        if user_id is not None:
            filters.append(PromptChain.user_id == user_id)
        chains = list(
            (
                await self.session.scalars(
                    select(PromptChain)
                    .where(*filters)
                    .order_by(PromptChain.updated_at.desc(), PromptChain.id.asc())
                )
            ).all()
        )
        if not chains:
            return []
        steps = list(
            (
                await self.session.scalars(
                    select(PromptChainStep)
                    .where(PromptChainStep.chain_id.in_([chain.id for chain in chains]))
                    .order_by(PromptChainStep.chain_id, PromptChainStep.position)
                )
            ).all()
        )
        grouped = {chain.id: [] for chain in chains}
        for step in steps:
            grouped[step.chain_id].append(step)
        return [(chain, grouped[chain.id]) for chain in chains]

    async def update(self, project: Project, values: dict[str, object]) -> Project:
        for key, value in values.items():
            setattr(project, key, value)
        await self.session.commit()
        await self.session.refresh(project)
        return project

    async def delete(self, project: Project) -> None:
        await self.session.execute(update(Prompt).where(Prompt.project_id == project.id).values(project_id=None))
        await self.session.execute(
            update(PromptTemplate).where(PromptTemplate.project_id == project.id).values(project_id=None)
        )
        await self.session.delete(project)
        await self.session.commit()
