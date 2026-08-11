from datetime import UTC, datetime, timedelta
from hashlib import sha256
from secrets import token_urlsafe
from uuid import UUID

import jwt
from fastapi import status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.exceptions import DomainError
from app.core.security import create_access_token, create_refresh_token, decode_token, hash_password, verify_password
from app.modules.auth.repository import AuthRepository
from app.modules.auth.schemas import TokenPair
from app.modules.billing.service import BillingService
from app.modules.users.model import User
from app.modules.users.repository import UserRepository
from app.modules.users.schemas import AdminUserCreate, UserCreate


class AuthService:
    def __init__(self, session: AsyncSession) -> None:
        self.users = UserRepository(session)
        self.tokens = AuthRepository(session)

    @staticmethod
    def _is_expired(expires_at: datetime) -> bool:
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=UTC)
        return expires_at <= datetime.now(UTC)

    async def register(self, data: UserCreate | AdminUserCreate) -> User:
        if await self.users.get_by_email(str(data.email)):
            raise DomainError("An account with this email already exists", status.HTTP_409_CONFLICT)
        user = await self.users.create(
            email=str(data.email),
            full_name=data.full_name,
            hashed_password=hash_password(data.password),
        )
        await BillingService(self.users.session).provision_trial(user.id)
        if isinstance(data, AdminUserCreate):
            return await self.users.update(user, role=data.role, is_active=data.is_active)
        return user

    async def authenticate(self, email: str, password: str) -> User:
        user = await self.users.get_by_email(email)
        if user is None or not verify_password(password, user.hashed_password):
            raise DomainError("Invalid email or password", status.HTTP_401_UNAUTHORIZED)
        if not user.is_active:
            raise DomainError("User account is inactive", status.HTTP_403_FORBIDDEN)
        return user

    async def issue_tokens(self, user: User) -> TokenPair:
        subject = str(user.id)
        access_token = create_access_token(subject)
        refresh_token = create_refresh_token(subject)
        payload = decode_token(refresh_token, "refresh")
        expires_at = datetime.fromtimestamp(payload["exp"], tz=UTC)
        await self.tokens.store_refresh_token(user.id, payload["jti"], expires_at)
        return TokenPair(access_token=access_token, refresh_token=refresh_token)

    async def refresh(self, refresh_token: str) -> TokenPair:
        try:
            payload = decode_token(refresh_token, "refresh")
            token = await self.tokens.get_refresh_token(payload["jti"])
        except jwt.PyJWTError as exc:
            raise DomainError("Invalid refresh token", status.HTTP_401_UNAUTHORIZED) from exc
        if token is None or token.revoked_at is not None or self._is_expired(token.expires_at):
            raise DomainError("Invalid refresh token", status.HTTP_401_UNAUTHORIZED)
        user = await self.users.get_by_id(UUID(payload["sub"]))
        if user is None or not user.is_active:
            raise DomainError("User account is inactive", status.HTTP_403_FORBIDDEN)
        await self.tokens.revoke_refresh_token(token, datetime.now(UTC))
        return await self.issue_tokens(user)

    async def logout(self, refresh_token: str) -> None:
        try:
            payload = decode_token(refresh_token, "refresh")
        except jwt.PyJWTError as exc:
            raise DomainError("Invalid refresh token", status.HTTP_401_UNAUTHORIZED) from exc
        token = await self.tokens.get_refresh_token(payload["jti"])
        if token is None or token.revoked_at is not None:
            raise DomainError("Invalid refresh token", status.HTTP_401_UNAUTHORIZED)
        await self.tokens.revoke_refresh_token(token, datetime.now(UTC))

    async def change_password(self, user: User, current_password: str, new_password: str) -> None:
        if not verify_password(current_password, user.hashed_password):
            raise DomainError("Invalid current password", status.HTTP_400_BAD_REQUEST)
        user.hashed_password = hash_password(new_password)
        await self.users.update(user)
        await self.tokens.revoke_all_refresh_tokens(user.id, datetime.now(UTC))

    async def request_password_reset(self, email: str) -> str | None:
        user = await self.users.get_by_email(email)
        if user is None or not user.is_active:
            return None
        raw_token = token_urlsafe(32)
        expires_at = datetime.now(UTC) + timedelta(minutes=get_settings().password_reset_token_expire_minutes)
        await self.tokens.create_password_reset_token(user.id, sha256(raw_token.encode()).hexdigest(), expires_at)
        return raw_token

    async def reset_password(self, raw_token: str, new_password: str) -> None:
        token = await self.tokens.get_password_reset_token(sha256(raw_token.encode()).hexdigest())
        if token is None or token.used_at is not None or self._is_expired(token.expires_at):
            raise DomainError("Invalid or expired reset token", status.HTTP_400_BAD_REQUEST)
        user = await self.users.get_by_id(token.user_id)
        if user is None:
            raise DomainError("Invalid or expired reset token", status.HTTP_400_BAD_REQUEST)
        user.hashed_password = hash_password(new_password)
        await self.users.update(user)
        await self.tokens.use_password_reset_token(token, datetime.now(UTC))
        await self.tokens.revoke_all_refresh_tokens(user.id, datetime.now(UTC))
