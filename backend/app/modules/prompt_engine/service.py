from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.ai_gateway.schemas import GenerateTextRequest, TokenUsageResponse
from app.modules.ai_gateway.service import AIGatewayService
from app.modules.billing.model import UsageRecord
from app.modules.billing.service import BillingService
from app.modules.prompt_engine.builder import PromptBuilder
from app.modules.prompt_engine.enums import PromptStatus
from app.modules.prompt_engine.model import Prompt
from app.modules.prompt_engine.repository import PromptRepository
from app.modules.prompt_engine.schemas import PromptGenerateRequest, PromptGenerateResponse, PromptUpdateRequest
from app.modules.users.model import User
from app.modules.users.roles import Role


class PromptService:
    def __init__(
        self,
        session: AsyncSession,
        ai_gateway: AIGatewayService | None = None,
        billing: BillingService | None = None,
    ) -> None:
        self.repository = PromptRepository(session)
        self.ai_gateway = ai_gateway
        self.billing = billing
        self.builder = PromptBuilder()

    async def generate(self, user: User, data: PromptGenerateRequest) -> PromptGenerateResponse:
        generated = self.builder.build(data)
        provider = model = None
        usage = None
        prompt_status = PromptStatus.GENERATED
        reservation: UsageRecord | None = None
        if data.optimize_with_ai:
            if self.ai_gateway is None:
                raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="AI Gateway unavailable")
            if self.billing is not None:
                reservation = await self.billing.reserve_ai_generation(user.id, data.provider)
            try:
                optimized = await self.ai_gateway.generate(
                    GenerateTextRequest(
                        provider=data.provider,
                        model=data.model,
                        system_prompt=(
                            "Otimize o prompt fornecido preservando todas as seções, intenção, idioma e restrições. "
                            "Retorne somente o prompt final."
                        ),
                        user_prompt=generated,
                        temperature=0.2,
                        max_output_tokens=2_000,
                    )
                )
            except Exception:
                if reservation is not None:
                    await self.billing.repository.release_usage(reservation)
                raise
            generated = optimized.text
            provider, model, usage = optimized.provider, optimized.model, optimized.usage
            prompt_status = PromptStatus.OPTIMIZED
        prompt = await self.repository.create(
            user_id=user.id,
            title=data.title or self._title(data.input),
            original_input=data.input,
            generated_prompt=generated,
            category=data.category,
            language=data.language,
            tone=data.tone,
            mode=data.mode,
            status=prompt_status,
            provider=provider,
            model=model,
            input_tokens=usage.input_tokens if usage else None,
            output_tokens=usage.output_tokens if usage else None,
            total_tokens=usage.total_tokens if usage else None,
        )
        response = PromptGenerateResponse.model_validate(prompt)
        if reservation is not None and usage is not None:
            await self.billing.repository.finalize_usage(
                reservation,
                prompt_id=prompt.id,
                provider=provider or data.provider,
                model=model or data.model or "unknown",
                input_tokens=usage.input_tokens or 0,
                output_tokens=usage.output_tokens or 0,
            )
        return response.model_copy(update={"usage": TokenUsageResponse.model_validate(usage) if usage else None})

    async def accessible(self, prompt_id: UUID, user: User) -> Prompt:
        prompt = await self.repository.get_by_id(prompt_id)
        # A uniform 404 prevents disclosure of another user's prompt identifiers.
        if prompt is None or (prompt.user_id != user.id and user.role != Role.ADMIN):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Prompt not found")
        return prompt

    async def update(self, prompt_id: UUID, user: User, data: PromptUpdateRequest) -> Prompt:
        prompt = await self.accessible(prompt_id, user)
        return await self.repository.update(prompt, **data.model_dump(exclude_unset=True))

    async def delete(self, prompt_id: UUID, user: User) -> None:
        await self.repository.delete(await self.accessible(prompt_id, user))

    @staticmethod
    def _title(original_input: str) -> str:
        compact = " ".join(original_input.split())
        return compact if len(compact) <= 80 else f"{compact[:77].rstrip()}..."
