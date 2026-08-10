from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.users.model import User


class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_by_email(self, email: str) -> User | None:
        return await self.session.scalar(select(User).where(User.email == email.lower()))

    async def get_by_id(self, user_id: UUID) -> User | None:
        return await self.session.get(User, user_id)

    async def create(self, *, email: str, full_name: str, hashed_password: str) -> User:
        user = User(email=email.lower(), full_name=full_name, hashed_password=hashed_password)
        self.session.add(user)
        await self.session.commit()
        await self.session.refresh(user)
        return user

    async def list(self, offset: int, limit: int) -> tuple[list[User], int]:
        statement = select(User).order_by(User.created_at.desc()).offset(offset).limit(limit)
        users = list((await self.session.scalars(statement)).all())
        total = await self.session.scalar(select(func.count()).select_from(User))
        return users, total or 0

    async def update(self, user: User, **values: object) -> User:
        for field, value in values.items():
            if value is not None:
                setattr(user, field, value)
        await self.session.commit()
        await self.session.refresh(user)
        return user

    async def delete(self, user: User) -> None:
        await self.session.delete(user)
        await self.session.commit()
