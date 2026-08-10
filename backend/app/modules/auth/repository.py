from datetime import datetime
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.auth.model import PasswordResetToken, RefreshToken


class AuthRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def store_refresh_token(self, user_id: UUID, token_jti: str, expires_at: datetime) -> RefreshToken:
        token = RefreshToken(user_id=user_id, token_jti=token_jti, expires_at=expires_at)
        self.session.add(token)
        await self.session.commit()
        await self.session.refresh(token)
        return token

    async def get_refresh_token(self, token_jti: str) -> RefreshToken | None:
        return await self.session.scalar(select(RefreshToken).where(RefreshToken.token_jti == token_jti))

    async def revoke_refresh_token(self, token: RefreshToken, revoked_at: datetime) -> None:
        token.revoked_at = revoked_at
        await self.session.commit()

    async def revoke_all_refresh_tokens(self, user_id: UUID, revoked_at: datetime) -> None:
        await self.session.execute(
            update(RefreshToken)
            .where(RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=revoked_at)
        )
        await self.session.commit()

    async def create_password_reset_token(
        self, user_id: UUID, token_hash: str, expires_at: datetime
    ) -> PasswordResetToken:
        token = PasswordResetToken(user_id=user_id, token_hash=token_hash, expires_at=expires_at)
        self.session.add(token)
        await self.session.commit()
        await self.session.refresh(token)
        return token

    async def get_password_reset_token(self, token_hash: str) -> PasswordResetToken | None:
        return await self.session.scalar(select(PasswordResetToken).where(PasswordResetToken.token_hash == token_hash))

    async def use_password_reset_token(self, token: PasswordResetToken, used_at: datetime) -> None:
        token.used_at = used_at
        await self.session.commit()
