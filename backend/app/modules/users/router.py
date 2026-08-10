from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.modules.auth.service import AuthService
from app.modules.users.dependencies import DbSession, get_current_user, require_permission
from app.modules.users.model import User
from app.modules.users.repository import UserRepository
from app.modules.users.roles import Permission
from app.modules.users.schemas import AdminUserCreate, PasswordChange, UserPage, UserRead, UserUpdate

router = APIRouter()


@router.get("/me", response_model=UserRead, summary="Obtém o usuário autenticado")
async def get_me(current_user: Annotated[User, Depends(get_current_user)]) -> User:
    return current_user


@router.patch("/me/password", status_code=status.HTTP_204_NO_CONTENT, summary="Altera a senha do usuário autenticado")
async def change_my_password(
    data: PasswordChange,
    session: DbSession,
    current_user: Annotated[User, Depends(get_current_user)],
) -> None:
    await AuthService(session).change_password(current_user, data.current_password, data.new_password)


@router.post(
    "", response_model=UserRead, status_code=status.HTTP_201_CREATED, summary="Cria um usuário como administrador"
)
async def create_user_as_admin(
    data: AdminUserCreate,
    session: DbSession,
    _: Annotated[User, Depends(require_permission(Permission.USERS_MANAGE))],
) -> User:
    return await AuthService(session).register(data)


@router.get("", response_model=UserPage, summary="Lista usuários")
async def list_users(
    session: DbSession,
    _: Annotated[User, Depends(require_permission(Permission.USERS_READ))],
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
) -> UserPage:
    users, total = await UserRepository(session).list(offset, limit)
    return UserPage(items=users, total=total)


@router.get("/{user_id}", response_model=UserRead, summary="Obtém um usuário")
async def get_user(
    user_id: UUID,
    session: DbSession,
    current_user: Annotated[User, Depends(get_current_user)],
) -> User:
    user = await UserRepository(session).get_by_id(user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    if user.id != current_user.id and not current_user.role.value == "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")
    return user


@router.patch("/{user_id}", response_model=UserRead, summary="Atualiza um usuário")
async def update_user(
    user_id: UUID,
    data: UserUpdate,
    session: DbSession,
    current_user: Annotated[User, Depends(get_current_user)],
) -> User:
    repository = UserRepository(session)
    user = await repository.get_by_id(user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    is_admin = current_user.role.value == "admin"
    if user.id != current_user.id and not is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")
    values = data.model_dump(exclude_unset=True)
    if not is_admin:
        values.pop("is_active", None)
        values.pop("role", None)
    if "email" in values and await repository.get_by_email(str(values["email"])) not in (None, user):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="An account with this email already exists")
    return await repository.update(user, **values)


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Remove um usuário")
async def delete_user(
    user_id: UUID,
    session: DbSession,
    _: Annotated[User, Depends(require_permission(Permission.USERS_MANAGE))],
) -> None:
    repository = UserRepository(session)
    user = await repository.get_by_id(user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    await repository.delete(user)
