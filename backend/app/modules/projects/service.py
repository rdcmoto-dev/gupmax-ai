from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.projects.model import Project
from app.modules.projects.repository import ProjectRepository
from app.modules.projects.schemas import ProjectCreate, ProjectDetail, ProjectRead, ProjectUpdate
from app.modules.prompt_engine.repository import PromptRepository
from app.modules.prompt_templates.repository import PromptTemplateRepository
from app.modules.users.model import User


class ProjectService:
    def __init__(self, session: AsyncSession) -> None:
        self.repository = ProjectRepository(session)
        self.prompts = PromptRepository(session)
        self.templates = PromptTemplateRepository(session)

    async def accessible(self, project_id: UUID, user: User) -> Project:
        project = await self.repository.get(project_id)
        if project is None or project.user_id != user.id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Project not found")
        return project

    async def create(self, user: User, data: ProjectCreate) -> Project:
        return await self.repository.create(user_id=user.id, **data.model_dump())

    async def read(self, project: Project) -> ProjectRead:
        prompts, templates = await self.repository.counts(project.id)
        return ProjectRead.model_validate(project).model_copy(
            update={"prompt_count": prompts, "template_count": templates}
        )

    async def detail(self, project_id: UUID, user: User) -> ProjectDetail:
        project = await self.accessible(project_id, user)
        prompts, templates = await self.repository.contents(project.id)
        summary = await self.read(project)
        return ProjectDetail(
            **summary.model_dump(),
            prompts=prompts,
            templates=templates,
        )

    async def update(self, project_id: UUID, user: User, data: ProjectUpdate) -> Project:
        return await self.repository.update(
            await self.accessible(project_id, user), data.model_dump(exclude_unset=True)
        )

    async def delete(self, project_id: UUID, user: User) -> None:
        await self.repository.delete(await self.accessible(project_id, user))

    async def assign_prompt(self, project_id: UUID, prompt_id: UUID, user: User) -> None:
        project = await self.accessible(project_id, user)
        prompt = await self.prompts.get_by_id(prompt_id)
        if prompt is None or prompt.user_id != user.id:
            raise HTTPException(status_code=404, detail="Prompt not found")
        await self.prompts.update(prompt, project_id=project.id)

    async def unassign_prompt(self, project_id: UUID, prompt_id: UUID, user: User) -> None:
        await self.accessible(project_id, user)
        prompt = await self.prompts.get_by_id(prompt_id)
        if prompt is None or prompt.user_id != user.id or prompt.project_id != project_id:
            raise HTTPException(status_code=404, detail="Prompt not found")
        prompt.project_id = None
        await self.prompts.session.commit()

    async def assign_template(self, project_id: UUID, template_id: UUID, user: User) -> None:
        project = await self.accessible(project_id, user)
        template = await self.templates.get(template_id)
        if template is None or template.user_id != user.id:
            raise HTTPException(status_code=404, detail="Template not found")
        await self.templates.update(template, {"project_id": project.id})

    async def unassign_template(self, project_id: UUID, template_id: UUID, user: User) -> None:
        await self.accessible(project_id, user)
        template = await self.templates.get(template_id)
        if template is None or template.user_id != user.id or template.project_id != project_id:
            raise HTTPException(status_code=404, detail="Template not found")
        template.project_id = None
        await self.templates.session.commit()
