from uuid import UUID

from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.project_blueprints.model import ProjectBlueprint
from app.modules.project_blueprints.schemas import (
    BlueprintChain,
    BlueprintCreate,
    BlueprintPage,
    BlueprintRead,
    BlueprintStep,
    BlueprintStructure,
    BlueprintUpdate,
    BlueprintUse,
)
from app.modules.projects.memory import ProjectMemory
from app.modules.projects.model import Project, ProjectStatus
from app.modules.projects.service import ProjectService
from app.modules.prompt_chains.model import PromptChain, PromptChainStatus, PromptChainStep, PromptChainStepStatus
from app.modules.prompt_engine.enums import PromptCategory
from app.modules.users.model import User

MAX_STRUCTURE_BYTES = 1_048_576


def reusable_structure(context: str | None) -> dict:
    values: dict = {"objective": None, "success_criteria": [], "milestones": []}
    remaining = []
    for line in (ProjectMemory.reusable_context(context) or "").splitlines():
        label, separator, value = line.partition(":")
        key = ProjectMemory._fold(label) if separator else ""
        if key in ProjectMemory.OBJECTIVE_LABELS:
            values["objective"] = value.strip()
        elif key in ProjectMemory.SUCCESS_CRITERION_LABELS:
            values["success_criteria"].append(value.strip())
        elif key in {"marco", "milestone"}:
            values["milestones"].append(value.strip())
        elif key not in {"resultado anterior", "resultado anterior operacional"}:
            remaining.append(line)
    values["context"] = "\n".join(remaining) or None
    return values


def project_context(structure: BlueprintStructure) -> str | None:
    lines = [f"Objetivo: {structure.objective}"] if structure.objective else []
    lines.extend(f"Critério de sucesso: {item}" for item in structure.success_criteria)
    lines.extend(f"Marco: {item}" for item in structure.milestones)
    if structure.context:
        lines.append(structure.context)
    return ProjectMemory.normalize_context("\n".join(lines))


class BlueprintService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def accessible(self, blueprint_id: UUID, user: User) -> ProjectBlueprint:
        row = await self.session.scalar(
            select(ProjectBlueprint).where(ProjectBlueprint.id == blueprint_id, ProjectBlueprint.user_id == user.id)
        )
        if row is None:
            raise HTTPException(status_code=404, detail="Project blueprint not found")
        return row

    async def list(self, user: User, offset: int, limit: int) -> BlueprintPage:
        scope = ProjectBlueprint.user_id == user.id
        rows = (
            await self.session.scalars(
                select(ProjectBlueprint)
                .where(scope)
                .order_by(ProjectBlueprint.updated_at.desc(), ProjectBlueprint.id)
                .offset(offset)
                .limit(limit)
            )
        ).all()
        total = await self.session.scalar(select(func.count()).select_from(ProjectBlueprint).where(scope))
        return BlueprintPage(
            items=[BlueprintRead.model_validate(row) for row in rows], total=total or 0, offset=offset, limit=limit
        )

    async def create(self, user: User, data: BlueprintCreate) -> ProjectBlueprint:
        projects = ProjectService(self.session)
        source = await projects.accessible(data.source_project_id, user)
        rows = await projects.repository.project_chains(source.id, user.id)
        try:
            structure = BlueprintStructure(
                project_name=source.name,
                description=source.description,
                **reusable_structure(source.context),
                chains=[
                    BlueprintChain(
                        name=chain.name,
                        description=chain.description,
                        steps=[
                            BlueprintStep(
                                title=step.title,
                                base_input=step.base_input,
                                mode=step.mode,
                                category=step.category,
                                target_ai=step.target_ai,
                            )
                            for step in steps
                        ],
                    )
                    for chain, steps in rows
                ],
            )
            if len(structure.model_dump_json().encode("utf-8")) > MAX_STRUCTURE_BYTES:
                raise HTTPException(status_code=413, detail="Project structure exceeds blueprint limits")
        except (ValidationError, ValueError) as error:
            raise HTTPException(status_code=413, detail="Project structure exceeds blueprint limits") from error
        category = next((step.category for chain in structure.chains for step in chain.steps), PromptCategory.GENERAL)
        blueprint = ProjectBlueprint(
            user_id=user.id,
            name=data.name,
            description=data.description,
            category=category,
            structure=structure.model_dump(mode="json"),
        )
        try:
            self.session.add(blueprint)
            await self.session.commit()
            await self.session.refresh(blueprint)
            return blueprint
        except Exception:
            await self.session.rollback()
            raise

    async def update(self, blueprint_id: UUID, user: User, data: BlueprintUpdate) -> ProjectBlueprint:
        row = await self.accessible(blueprint_id, user)
        for key, value in data.model_dump().items():
            setattr(row, key, value)
        await self.session.commit()
        await self.session.refresh(row)
        return row

    async def delete(self, blueprint_id: UUID, user: User) -> None:
        await self.session.delete(await self.accessible(blueprint_id, user))
        await self.session.commit()

    async def use(self, blueprint_id: UUID, user: User, data: BlueprintUse) -> Project:
        blueprint = await self.accessible(blueprint_id, user)
        structure = BlueprintStructure.model_validate(blueprint.structure)
        project = Project(
            user_id=user.id,
            name=data.name,
            description=structure.description,
            context=project_context(structure),
            status=ProjectStatus.ACTIVE,
            is_favorite=False,
        )
        try:
            self.session.add(project)
            await self.session.flush()
            for source in structure.chains:
                chain = PromptChain(
                    user_id=user.id,
                    project_id=project.id,
                    name=source.name,
                    description=source.description,
                    status=PromptChainStatus.ACTIVE,
                )
                self.session.add(chain)
                await self.session.flush()
                self.session.add_all(
                    PromptChainStep(
                        chain_id=chain.id,
                        position=position,
                        **step.model_dump(),
                        execution_status=PromptChainStepStatus.PENDING,
                    )
                    for position, step in enumerate(source.steps, start=1)
                )
            await self.session.commit()
            await self.session.refresh(project)
            return project
        except Exception:
            await self.session.rollback()
            raise
