from fastapi import APIRouter, status

from app.modules.auth.schemas import (
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegistrationResponse,
    TokenPair,
    UserCreate,
)
from app.modules.auth.service import AuthService
from app.modules.users.dependencies import DbSession
from app.modules.users.schemas import PasswordResetConfirm, PasswordResetRequest

router = APIRouter()


@router.post(
    "/register",
    response_model=RegistrationResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Cria uma conta de usuário",
)
async def register(data: UserCreate, session: DbSession) -> RegistrationResponse:
    service = AuthService(session)
    user = await service.register(data)
    tokens = await service.issue_tokens(user)
    return RegistrationResponse(**tokens.model_dump(), user=user)


@router.post("/login", response_model=TokenPair, summary="Autentica e emite tokens JWT")
async def login(data: LoginRequest, session: DbSession) -> TokenPair:
    service = AuthService(session)
    user = await service.authenticate(str(data.email), data.password)
    return await service.issue_tokens(user)


@router.post("/refresh", response_model=TokenPair, summary="Rotaciona um refresh token válido")
async def refresh(data: RefreshRequest, session: DbSession) -> TokenPair:
    return await AuthService(session).refresh(data.refresh_token)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT, summary="Revoga um refresh token")
async def logout(data: LogoutRequest, session: DbSession) -> None:
    await AuthService(session).logout(data.refresh_token)


@router.post(
    "/password-recovery",
    status_code=status.HTTP_202_ACCEPTED,
    summary="Solicita recuperação de senha",
)
async def request_password_recovery(data: PasswordResetRequest, session: DbSession) -> None:
    await AuthService(session).request_password_reset(str(data.email))


@router.post("/password-reset", status_code=status.HTTP_204_NO_CONTENT, summary="Redefine a senha com token válido")
async def reset_password(data: PasswordResetConfirm, session: DbSession) -> None:
    await AuthService(session).reset_password(data.token, data.new_password)
