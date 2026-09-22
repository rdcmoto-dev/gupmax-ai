from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import jwt
from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.modules.auth.model import RefreshToken
from app.modules.auth.schemas import InvitationResponse, InvitedUserCreate, RegistrationResponse
from app.modules.auth.service import AuthService
from app.modules.users.model import User
from app.modules.users.repository import UserRepository
from app.modules.users.roles import Permission, has_permission
from app.modules.users.schemas import UserCreate

INVITATION_LIFETIME = timedelta(hours=72)
INVITATION_AUDIENCE = "pilot-registration"


@dataclass(frozen=True)
class InvitationClaims:
    jti: str
    email: str


def denied() -> HTTPException:
    return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Registration requires an invitation")


async def issue_invitation(session: AsyncSession, issuer: User, email: str) -> InvitationResponse:
    if not issuer.is_active or not has_permission(issuer.role, Permission.USERS_MANAGE):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")
    email = email.lower()
    if await UserRepository(session).get_by_email(email):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="An account with this email already exists")
    now = datetime.now(UTC)
    expires_at = now + INVITATION_LIFETIME
    # Separate namespace, within the existing 36-character column. Keeping this
    # row on the issuer prevents replay after the invitee changes email or is deleted.
    jti = f"inv:{uuid4().hex}"
    settings = get_settings()
    token = jwt.encode(
        {"sub": email, "type": "invitation", "jti": jti, "iat": now, "exp": expires_at,
         "aud": INVITATION_AUDIENCE},
        settings.jwt_secret_key, algorithm=settings.jwt_algorithm,
    )
    session.add(RefreshToken(user_id=issuer.id, token_jti=jti, expires_at=expires_at))
    await session.commit()
    return InvitationResponse(invitation_token=token, expires_at=expires_at)


async def require_registration_access(data: InvitedUserCreate) -> InvitationClaims:
    if data.invitation_token is None:
        raise denied()
    settings = get_settings()
    try:
        claims = jwt.decode(
            data.invitation_token.get_secret_value(), settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm], audience=INVITATION_AUDIENCE,
            options={"require": ["sub", "type", "jti", "iat", "exp", "aud"]},
        )
        jti = claims["jti"]
        if (claims["type"] != "invitation" or claims["sub"] != str(data.email).lower()
                or not isinstance(jti, str) or not jti.startswith("inv:") or len(jti) != 36):
            raise denied()
    except jwt.PyJWTError as exc:
        raise denied() from exc
    return InvitationClaims(jti=jti, email=claims["sub"])


async def register_invited(
    session: AsyncSession, data: UserCreate, invitation: InvitationClaims,
) -> RegistrationResponse:
    # Existing repository commits flush only inside this enclosing transaction.
    # Any failure rolls back account, trial, credits, tokens and consumption together.
    connection = await session.connection()
    try:
        async with AsyncSession(bind=connection, join_transaction_mode="rollback_only", expire_on_commit=False) as unit:
            record = await unit.scalar(
                select(RefreshToken).where(RefreshToken.token_jti == invitation.jti).with_for_update()
            )
            if record is None or record.revoked_at is not None or AuthService._is_expired(record.expires_at):
                raise denied()
            issuer = await unit.get(User, record.user_id)
            if (issuer is None or not issuer.is_active
                    or not has_permission(issuer.role, Permission.USERS_MANAGE)
                    or str(data.email).lower() != invitation.email):
                raise denied()
            record.revoked_at = datetime.now(UTC)
            service = AuthService(unit)
            user = await service.register(data)
            tokens = await service.issue_tokens(user)
            result = RegistrationResponse(**tokens.model_dump(), user=user)
        await session.commit()
        return result
    except IntegrityError as exc:
        await session.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Registration conflict") from exc
    except Exception:
        await session.rollback()
        raise
