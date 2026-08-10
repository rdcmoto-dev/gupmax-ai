from pydantic import BaseModel, EmailStr, Field

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


__all__ = ["LoginRequest", "RefreshRequest", "RegistrationResponse", "TokenPair", "UserCreate"]
