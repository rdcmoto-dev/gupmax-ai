from uuid import UUID

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.projects.model import Project, ProjectStatus
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

    async def list(
        self, user_id: UUID, offset: int, limit: int, include_archived: bool
    ) -> tuple[list[Project], int]:
        filters = [Project.user_id == user_id]
        if not include_archived:
            filters.append(Project.status == ProjectStatus.ACTIVE)
        items = list(
            (await self.session.scalars(
                select(Project).where(*filters).order_by(Project.updated_at.desc()).offset(offset).limit(limit)
            )).all()
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

    async def contents(self, project_id: UUID) -> tuple[list[Prompt], list[PromptTemplate]]:
        prompts = list((await self.session.scalars(
            select(Prompt).where(Prompt.project_id == project_id).order_by(Prompt.updated_at.desc())
        )).all())
        templates = list((await self.session.scalars(
            select(PromptTemplate)
            .where(PromptTemplate.project_id == project_id)
            .order_by(PromptTemplate.updated_at.desc())
        )).all())
        return prompts, templates

    async def update(self, project: Project, values: dict[str, object]) -> Project:
        for key, value in values.items():
            setattr(project, key, value)
        await self.session.commit()
        await self.session.refresh(project)
        return project

    async def delete(self, project: Project) -> None:
        await self.session.execute(
            update(Prompt).where(Prompt.project_id == project.id).values(project_id=None)
        )
        await self.session.execute(
            update(PromptTemplate).where(PromptTemplate.project_id == project.id).values(project_id=None)
        )
        await self.session.delete(project)
        await self.session.commit()
