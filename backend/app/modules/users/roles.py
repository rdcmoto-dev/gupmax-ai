from enum import StrEnum


class Role(StrEnum):
    USER = "user"
    ADMIN = "admin"


class Permission(StrEnum):
    USERS_READ = "users:read"
    USERS_MANAGE = "users:manage"
    BILLING_MANAGE = "billing:manage"


ROLE_PERMISSIONS: dict[Role, frozenset[Permission]] = {
    Role.USER: frozenset(),
    Role.ADMIN: frozenset({Permission.USERS_READ, Permission.USERS_MANAGE, Permission.BILLING_MANAGE}),
}


def has_permission(role: Role, permission: Permission) -> bool:
    return permission in ROLE_PERMISSIONS[role]
