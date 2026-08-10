from typing import Annotated
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import decode_token
from app.db.session import get_db_session
from app.modules.users.model import User
from app.modules.users.repository import UserRepository
from app.modules.users.roles import Permission, has_permission

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")
DbSession = Annotated[AsyncSession, Depends(get_db_session)]


async def get_current_user(session: DbSession, token: Annotated[str, Depends(oauth2_scheme)]) -> User:
    credentials_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        subject = decode_token(token, "access")["sub"]
        user_id = UUID(subject)
    except (jwt.PyJWTError, ValueError) as exc:
        raise credentials_error from exc
    user = await UserRepository(session).get_by_id(user_id)
    if user is None or not user.is_active:
        raise credentials_error
    return user


def require_permission(permission: Permission):
    async def dependency(current_user: Annotated[User, Depends(get_current_user)]) -> User:
        if not has_permission(current_user.role, permission):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")
        return current_user

    return dependency
