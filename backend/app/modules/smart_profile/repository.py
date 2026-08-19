from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.smart_profile.model import UserPromptPreferences


class SmartProfileRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get(self, user_id: UUID) -> UserPromptPreferences | None:
        return await self.session.scalar(
            select(UserPromptPreferences).where(UserPromptPreferences.user_id == user_id)
        )

    async def upsert(self, user_id: UUID, values: dict[str, object]) -> UserPromptPreferences:
        profile = await self.get(user_id)
        if profile is None:
            profile = UserPromptPreferences(user_id=user_id, **values)
            self.session.add(profile)
        else:
            for key, value in values.items():
                setattr(profile, key, value)
        await self.session.commit()
        await self.session.refresh(profile)
        return profile

    async def delete(self, profile: UserPromptPreferences) -> None:
        await self.session.delete(profile)
        await self.session.commit()
