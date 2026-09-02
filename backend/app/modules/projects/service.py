from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.projects.model import Project
from app.modules.projects.repository import ProjectRepository
from app.modules.projects.schemas import (
    ProjectActivityItem,
    ProjectCreate,
    ProjectDetail,
    ProjectLibraryChain,
    ProjectLibraryPage,
    ProjectLibraryPrompt,
    ProjectLibraryStep,
    ProjectRead,
    ProjectUpdate,
)
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

    async def library(self, project_id: UUID, user: User, offset: int, limit: int) -> ProjectLibraryPage:
        project = await self.accessible(project_id, user)
        prompt_rows, prompt_total = await self.repository.library_prompts(project.id, offset, limit)
        chain_rows = await self.repository.project_chains(project.id)
        prompts = [
            ProjectLibraryPrompt(
                id=prompt.id,
                title=prompt.title,
                category=prompt.category,
                mode=prompt.mode,
                target_ai=prompt.target_ai,
                version_count=version_count,
                created_at=prompt.created_at,
                updated_at=prompt.updated_at,
            )
            for prompt, version_count in prompt_rows
        ]
        chains: list[ProjectLibraryChain] = []
        activity: list[ProjectActivityItem] = [
            ProjectActivityItem(
                kind="project", label="Projeto atualizado", occurred_at=project.updated_at, stable_id=project.id
            )
        ]
        for prompt in prompts:
            activity.append(
                ProjectActivityItem(
                    kind="prompt",
                    label="Prompt criado" if prompt.version_count == 1 else "Prompt refinado",
                    occurred_at=prompt.updated_at,
                    stable_id=prompt.id,
                )
            )
        completed_total = 0
        for chain, steps in chain_rows:
            completed = [step for step in steps if step.execution_status == "completed"]
            completed_total += len(completed)
            current = next((step.id for step in steps if step.execution_status == "in_progress"), None)
            library_steps = [
                ProjectLibraryStep(
                    id=step.id,
                    position=step.position,
                    title=step.title,
                    status=step.execution_status,
                    has_result=bool(step.result),
                    result_preview=(step.result[:240] if step.result else None),
                    completed_at=step.completed_at,
                )
                for step in steps
            ]
            chains.append(
                ProjectLibraryChain(
                    id=chain.id,
                    name=chain.name,
                    completed_count=len(completed),
                    step_count=len(steps),
                    current_step_id=current,
                    steps=library_steps,
                    updated_at=chain.updated_at,
                )
            )
            activity.extend(
                ProjectActivityItem(
                    kind="step",
                    label=f"Etapa concluída: {step.title}",
                    occurred_at=step.completed_at,
                    stable_id=step.id,
                )
                for step in completed
                if step.completed_at is not None
            )
        activity.sort(key=lambda item: (item.occurred_at, str(item.stable_id)), reverse=True)
        last_activity = activity[0].occurred_at if activity else project.updated_at
        return ProjectLibraryPage(
            project_id=project.id,
            prompts=prompts,
            prompt_total=prompt_total,
            offset=offset,
            limit=limit,
            chains=chains,
            completed_step_count=completed_total,
            activity=activity[:20],
            last_activity_at=last_activity,
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
