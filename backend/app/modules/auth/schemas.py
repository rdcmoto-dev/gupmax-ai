from datetime import datetime

from pydantic import BaseModel, EmailStr, Field, SecretStr

from app.modules.users.schemas import UserCreate, UserRead


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class LogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RegistrationResponse(TokenPair):
    user: UserRead


class InvitedUserCreate(UserCreate):
    invitation_token: SecretStr | None = None


class InvitationRequest(BaseModel):
    email: EmailStr


class InvitationResponse(BaseModel):
    invitation_token: str
    expires_at: datetime


__all__ = ["LoginRequest", "RefreshRequest", "RegistrationResponse", "TokenPair", "UserCreate"]
