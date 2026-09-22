from typing import Annotated

from fastapi import APIRouter, Depends, Response, status

from app.modules.auth.registration import (
    InvitationClaims,
    issue_invitation,
    register_invited,
    require_registration_access,
)
from app.modules.auth.schemas import (
    InvitationRequest,
    InvitationResponse,
    InvitedUserCreate,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegistrationResponse,
    TokenPair,
)
from app.modules.auth.service import AuthService
from app.modules.users.dependencies import DbSession, require_permission
from app.modules.users.model import User
from app.modules.users.roles import Permission
from app.modules.users.schemas import PasswordResetConfirm, PasswordResetRequest, UserCreate

router = APIRouter()


@router.post(
    "/register",
    response_model=RegistrationResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Cria uma conta de usuário",
)
async def register(
    data: InvitedUserCreate,
    session: DbSession,
    invitation: Annotated[InvitationClaims, Depends(require_registration_access)],
    response: Response,
) -> RegistrationResponse:
    response.headers["Cache-Control"] = "no-store"
    user_data = UserCreate(email=data.email, full_name=data.full_name, password=data.password)
    return await register_invited(session, user_data, invitation)


@router.post("/invitations", response_model=InvitationResponse, status_code=status.HTTP_201_CREATED)
async def create_invitation(
    data: InvitationRequest,
    session: DbSession,
    issuer: Annotated[User, Depends(require_permission(Permission.USERS_MANAGE))],
    response: Response,
) -> InvitationResponse:
    response.headers["Cache-Control"] = "no-store"
    return await issue_invitation(session, issuer, str(data.email))


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
