from app.modules.users.roles import Permission, Role, has_permission


def test_administrator_has_user_management_permissions() -> None:
    assert has_permission(Role.ADMIN, Permission.USERS_MANAGE)
    assert has_permission(Role.ADMIN, Permission.USERS_READ)
    assert not has_permission(Role.USER, Permission.USERS_MANAGE)
