from app.modules.prompt_engine.schemas import PromptGenerateRequest
from app.modules.smart_profile.model import UserPromptPreferences
from app.modules.smart_profile.repository import SmartProfileRepository
from app.modules.smart_profile.schemas import SmartProfileRead, SmartProfileWrite
from app.modules.users.model import User


class SmartProfileService:
    def __init__(self, session) -> None:
        self.repository = SmartProfileRepository(session)

    async def get(self, user: User) -> SmartProfileRead:
        profile = await self.repository.get(user.id)
        return SmartProfileRead.model_validate(profile) if profile else SmartProfileRead(is_enabled=False)

    async def save(self, user: User, data: SmartProfileWrite) -> SmartProfileRead:
        profile = await self.repository.upsert(user.id, data.model_dump())
        return SmartProfileRead.model_validate(profile)

    async def delete(self, user: User) -> None:
        profile = await self.repository.get(user.id)
        if profile is not None:
            await self.repository.delete(profile)

    async def enabled(self, user_id) -> UserPromptPreferences | None:
        profile = await self.repository.get(user_id)
        return profile if profile is not None and profile.is_enabled else None

    @staticmethod
    def apply(data: PromptGenerateRequest, profile: UserPromptPreferences | None) -> PromptGenerateRequest:
        if profile is None:
            return data
        values = data.model_dump()
        fallbacks = {
            "language": profile.default_language,
            "tone": profile.default_tone,
            "audience": profile.default_audience,
            "context": profile.business_context,
            "output_format": profile.default_output_format,
        }
        for key, value in fallbacks.items():
            if value and (not values.get(key) or (key == "language" and key not in data.model_fields_set)):
                values[key] = value
        if not values["constraints"]:
            values["constraints"] = profile.default_constraints
        if not values["instructions"]:
            values["instructions"] = profile.default_instructions
        if profile.default_channel and not values.get("additional_information"):
            values["additional_information"] = f"Canal/plataforma: {profile.default_channel}"
        return PromptGenerateRequest.model_validate(values)
