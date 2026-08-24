import re
from uuid import UUID

from fastapi import HTTPException, status
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.prompt_engine.service import PromptService
from app.modules.prompt_templates.model import PromptTemplate
from app.modules.prompt_templates.repository import PromptTemplateRepository
from app.modules.prompt_templates.schemas import (
    TemplateCreate,
    TemplateFields,
    TemplateFromPrompt,
    TemplateUpdate,
)
from app.modules.users.model import User


class PromptTemplateService:
    def __init__(self, session: AsyncSession) -> None:
        self.repository = PromptTemplateRepository(session)
        self.prompts = PromptService(session)

    async def accessible(self, template_id: UUID, user: User) -> PromptTemplate:
        template = await self.repository.get(template_id)
        if template is None or template.user_id != user.id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Template not found")
        return template

    async def create(self, user: User, data: TemplateCreate) -> PromptTemplate:
        return await self.repository.create(user_id=user.id, source_prompt_id=None, **data.model_dump())

    async def from_prompt(self, prompt_id: UUID, user: User, data: TemplateFromPrompt) -> PromptTemplate:
        prompt = await self.prompts.accessible(prompt_id, user)
        sections = self._sections(prompt.generated_prompt)
        return await self.repository.create(
            user_id=user.id,
            source_prompt_id=prompt.id,
            project_id=prompt.project_id,
            name=data.name,
            description=data.description,
            category=prompt.category,
            mode=prompt.mode,
            target_ai=prompt.target_ai,
            template_content=prompt.generated_prompt,
            base_input=sections.get("OBJECTIVE", prompt.original_input),
            language=sections.get("LANGUAGE", prompt.language),
            tone=sections.get("TONE", prompt.tone),
            audience=sections.get("AUDIENCE"),
            context=sections.get("CONTEXT"),
            output_format=sections.get("OUTPUT FORMAT"),
            constraints=self._items(sections.get("CONSTRAINTS")),
            instructions=self._items(sections.get("INSTRUCTIONS")),
            additional_information=sections.get("ADDITIONAL INFORMATION"),
            is_active=True,
        )

    async def update(self, template_id: UUID, user: User, data: TemplateUpdate) -> PromptTemplate:
        template = await self.accessible(template_id, user)
        updates = data.model_dump(exclude_unset=True)
        current = {
            name: getattr(template, name)
            for name in TemplateFields.model_fields
            if hasattr(template, name)
        }
        try:
            TemplateFields.model_validate({**current, **updates})
        except ValidationError as exc:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="Template supports at most 20 variables",
            ) from exc
        return await self.repository.update(template, updates)

    async def delete(self, template_id: UUID, user: User) -> None:
        await self.repository.delete(await self.accessible(template_id, user))

    @staticmethod
    def _sections(content: str) -> dict[str, str]:
        return {
            match.group(1).strip(): match.group(2).strip()
            for match in re.finditer(r"^## ([^\n]+)\n(.*?)(?=\n\n## |\Z)", content, re.MULTILINE | re.DOTALL)
        }

    @staticmethod
    def _items(value: str | None) -> list[str]:
        return [line.removeprefix("- ").strip() for line in (value or "").splitlines() if line.strip()]
