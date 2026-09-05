import json
import re
import unicodedata
from collections import defaultdict
from datetime import UTC, datetime
from enum import StrEnum
from html import escape
from uuid import UUID

from fastapi import HTTPException, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.projects.memory import ProjectMemory
from app.modules.projects.model import Project, ProjectStatus
from app.modules.projects.repository import ProjectRepository
from app.modules.projects.service import ProjectService
from app.modules.prompt_chains.model import PromptChain, PromptChainStep
from app.modules.prompt_engine.enums import PromptCategory, PromptMode, TargetAI
from app.modules.prompt_engine.model import Prompt
from app.modules.users.model import User

MAX_EXPORT_PROMPTS = 1000
MAX_EXPORT_CHAINS = 100
MAX_EXPORT_STEPS = 1000
MAX_EXPORT_BYTES = 10 * 1024 * 1024


class ProjectExportFormat(StrEnum):
    JSON = "json"
    MARKDOWN = "markdown"


class ExportProject(BaseModel):
    name: str
    description: str | None
    status: str
    created_at: datetime
    updated_at: datetime


class ExportCheckItem(BaseModel):
    text: str
    completed: bool


class ExportContextItem(BaseModel):
    label: str | None
    value: str


class ExportStep(BaseModel):
    position: int
    title: str
    status: str
    result: str | None
    completed_at: datetime | None


class ExportChain(BaseModel):
    name: str
    status: str
    completed_count: int
    step_count: int
    steps: list[ExportStep]


class ExportPromptVersion(BaseModel):
    version: int
    content: str
    created_at: datetime
    updated_at: datetime


class ExportPrompt(BaseModel):
    title: str
    category: PromptCategory
    mode: PromptMode
    target_ai: TargetAI
    created_at: datetime
    updated_at: datetime
    version_count: int
    current_content: str
    versions: list[ExportPromptVersion]


class ExportReview(BaseModel):
    conclusion: str | None
    manual_status: str


class ProjectExport(BaseModel):
    export_version: int = 1
    exported_at: datetime
    project: ExportProject
    goal: str | None
    success_criteria: list[ExportCheckItem]
    milestones: list[ExportCheckItem]
    context: list[ExportContextItem]
    chains: list[ExportChain]
    prompts: list[ExportPrompt]
    review: ExportReview


class ProjectExportService:
    def __init__(self, session: AsyncSession) -> None:
        self.repository = ProjectRepository(session)
        self.projects = ProjectService(session)

    async def build(self, project_id: UUID, user: User) -> ProjectExport:
        # Ownership is deliberately established before any associated content query.
        project = await self.projects.accessible(project_id, user)
        prompts = await self.repository.export_prompts(project.id, user.id, MAX_EXPORT_PROMPTS)
        chain_rows = await self.repository.project_chains(project.id, user.id)
        self._check_volume(prompts, chain_rows)
        goal, criteria, milestones, context, conclusion, closed = self._memory(project.context)
        return ProjectExport(
            exported_at=datetime.now(UTC),
            project=ExportProject(
                name=project.name,
                description=project.description,
                status=self._project_status(project, closed),
                created_at=project.created_at,
                updated_at=project.updated_at,
            ),
            goal=goal,
            success_criteria=criteria,
            milestones=milestones,
            context=context,
            chains=[self._chain(chain, steps) for chain, steps in chain_rows],
            prompts=self._prompts(prompts),
            review=ExportReview(
                conclusion=conclusion,
                manual_status="closed" if closed else "active",
            ),
        )

    @staticmethod
    def _check_volume(
        prompts: list[Prompt], chain_rows: list[tuple[PromptChain, list[PromptChainStep]]]
    ) -> None:
        if len(prompts) > MAX_EXPORT_PROMPTS:
            raise HTTPException(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                detail="Project export has too many prompts",
            )
        if len(chain_rows) > MAX_EXPORT_CHAINS:
            raise HTTPException(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                detail="Project export has too many chains",
            )
        if sum(len(steps) for _, steps in chain_rows) > MAX_EXPORT_STEPS:
            raise HTTPException(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                detail="Project export has too many steps",
            )

    @staticmethod
    def _memory(value: str | None) -> tuple[
        str | None,
        list[ExportCheckItem],
        list[ExportCheckItem],
        list[ExportContextItem],
        str | None,
        bool,
    ]:
        goal = conclusion = None
        closed = False
        criteria: list[ExportCheckItem] = []
        milestones: list[ExportCheckItem] = []
        context: list[ExportContextItem] = []
        for line in (value or "").splitlines():
            label, separator, raw = line.partition(":")
            if not separator:
                context.append(ExportContextItem(label=None, value=line))
                continue
            folded = ProjectMemory._fold(label)
            item_value = raw.strip()
            completed = bool(re.match(r"^\[\s*x\s*\]\s*", item_value, re.IGNORECASE))
            clean_value = re.sub(r"^\[\s*x\s*\]\s*", "", item_value, flags=re.IGNORECASE)
            if folded in ProjectMemory.OBJECTIVE_LABELS:
                goal = clean_value
            elif folded in ProjectMemory.SUCCESS_CRITERION_LABELS:
                criteria.append(ExportCheckItem(text=clean_value, completed=completed))
            elif folded in {"marco", "milestone"}:
                milestones.append(ExportCheckItem(text=clean_value, completed=completed))
            elif folded in ProjectMemory.FINAL_CONCLUSION_LABELS:
                conclusion = clean_value
            elif folded in ProjectMemory.CLOSED_PROJECT_LABELS:
                closed = ProjectMemory._fold(clean_value) == "sim"
            else:
                context.append(ExportContextItem(label=label.strip(), value=item_value))
        return goal, criteria, milestones, context, conclusion, closed

    @staticmethod
    def _project_status(project: Project, closed: bool) -> str:
        if project.status == ProjectStatus.ARCHIVED:
            return "archived"
        return "closed" if closed else "active"

    @staticmethod
    def _chain(chain: PromptChain, steps: list[PromptChainStep]) -> ExportChain:
        exported_steps = [
            ExportStep(
                position=step.position,
                title=step.title,
                status=step.execution_status,
                result=step.result,
                completed_at=step.completed_at,
            )
            for step in steps
        ]
        return ExportChain(
            name=chain.name,
            status=chain.status,
            completed_count=sum(step.execution_status == "completed" for step in steps),
            step_count=len(steps),
            steps=exported_steps,
        )

    @staticmethod
    def _prompts(prompts: list[Prompt]) -> list[ExportPrompt]:
        grouped: dict[UUID, list[Prompt]] = defaultdict(list)
        for prompt in prompts:
            grouped[prompt.root_prompt_id or prompt.id].append(prompt)
        result: list[ExportPrompt] = []
        for versions in grouped.values():
            versions.sort(key=lambda prompt: (prompt.version_number, prompt.created_at, str(prompt.id)))
            current = versions[-1]
            root = next((item for item in versions if item.id == (item.root_prompt_id or item.id)), versions[0])
            result.append(
                ExportPrompt(
                    title=root.title,
                    category=current.category,
                    mode=current.mode,
                    target_ai=current.target_ai,
                    created_at=min(item.created_at for item in versions),
                    updated_at=max(item.updated_at for item in versions),
                    version_count=len(versions),
                    current_content=current.generated_prompt,
                    versions=[
                        ExportPromptVersion(
                            version=item.version_number,
                            content=item.generated_prompt,
                            created_at=item.created_at,
                            updated_at=item.updated_at,
                        )
                        for item in versions
                    ],
                )
            )
        result.sort(key=lambda item: (item.created_at, item.title.casefold()))
        return result


def safe_export_filename(name: str, export_format: ProjectExportFormat) -> str:
    plain = "".join(
        character
        for character in unicodedata.normalize("NFKD", name.casefold())
        if not unicodedata.combining(character)
    )
    slug = re.sub(r"[^a-z0-9]+", "-", plain).strip("-")[:100].rstrip("-")
    return f"{slug or 'projeto'}.{ 'json' if export_format == ProjectExportFormat.JSON else 'md'}"


def render_json(package: ProjectExport) -> bytes:
    return json.dumps(package.model_dump(mode="json"), ensure_ascii=False, indent=2).encode("utf-8")


def _quoted(value: str | None) -> str:
    if not value:
        return "_Não informado._"
    return "\n".join(f"> {escape(line)}" if line else ">" for line in value.splitlines())


def _inline(value: str) -> str:
    return re.sub(r"([\\`*_{}\[\]()#+.!|>-])", r"\\\1", escape(value).replace("\n", " "))


def _human_status(value: str) -> str:
    return {
        "active": "Ativo",
        "closed": "Encerrado",
        "archived": "Arquivado",
        "pending": "Pendente",
        "in_progress": "Atual",
        "completed": "Concluída",
    }.get(value, value)


def render_markdown(package: ProjectExport) -> bytes:
    lines = [
        f"# {_inline(package.project.name)}",
        "",
        "## Descrição",
        "",
        _quoted(package.project.description),
        "",
        f"**Estado:** {_human_status(package.project.status)}",
        f"**Última atualização:** {package.project.updated_at.isoformat()}",
        "",
        "## Objetivo",
        "",
        _quoted(package.goal),
        "",
        "## Critérios de sucesso",
        "",
    ]
    lines.extend(f"- [{'x' if item.completed else ' '}] {_inline(item.text)}" for item in package.success_criteria)
    if not package.success_criteria:
        lines.append("_Nenhum critério registrado._")
    lines.extend(["", "## Marcos", ""])
    lines.extend(f"- [{'x' if item.completed else ' '}] {_inline(item.text)}" for item in package.milestones)
    if not package.milestones:
        lines.append("_Nenhum marco registrado._")
    lines.extend(["", "## Contexto do projeto", ""])
    for item in package.context:
        lines.append(f"**{_inline(item.label)}:**" if item.label else "**Informação:**")
        lines.extend(["", _quoted(item.value), ""])
    if not package.context:
        lines.append("_Nenhum contexto registrado._")
    lines.extend(["", "## Progresso", ""])
    for chain in package.chains:
        lines.append(f"### {_inline(chain.name)}")
        lines.extend(["", f"{chain.completed_count} de {chain.step_count} etapas concluídas.", ""])
        for step in chain.steps:
            lines.append(f"{step.position}. {_inline(step.title)} — {_human_status(step.status)}")
    if not package.chains:
        lines.append("_Nenhum fluxo associado._")
    lines.extend(["", "## Etapas e resultados", ""])
    results = [(chain, step) for chain in package.chains for step in chain.steps if step.result]
    for chain, step in results:
        lines.extend(
            [
                f"### {_inline(chain.name)} — Etapa {step.position}: {_inline(step.title)}",
                "",
                _quoted(step.result),
                "",
            ]
        )
    if not results:
        lines.append("_Nenhum resultado registrado._")
    lines.extend(["", "## Prompts", ""])
    for prompt in package.prompts:
        lines.extend([
            f"### {_inline(prompt.title)}",
            "",
            f"- Categoria: {prompt.category}",
            f"- Modo: {prompt.mode}",
            f"- Target AI: {prompt.target_ai}",
            f"- Versões: {prompt.version_count}",
            "",
        ])
        for version in prompt.versions:
            lines.extend([f"#### Versão {version.version}", "", _quoted(version.content), ""])
    if not package.prompts:
        lines.append("_Nenhum prompt associado._")
    lines.extend([
        "",
        "## Revisão final",
        "",
        f"**Estado manual:** {_human_status(package.review.manual_status)}",
        "",
        "**Conclusão do projeto:**",
        "",
        _quoted(package.review.conclusion),
        "",
        f"_Exportado em {package.exported_at.isoformat()}._",
        "",
    ])
    return "\n".join(lines).encode("utf-8")


def enforce_file_size(content: bytes) -> None:
    if len(content) > MAX_EXPORT_BYTES:
        raise HTTPException(status_code=status.HTTP_413_CONTENT_TOO_LARGE, detail="Project export exceeds 10 MiB")
