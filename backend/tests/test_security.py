import jwt
import pytest

from app.core.security import create_access_token, create_refresh_token, decode_token, hash_password, verify_password


def test_password_hash_round_trip() -> None:
    password = "correct-horse-battery-staple"
    assert verify_password(password, hash_password(password))


def test_access_token_round_trip() -> None:
    token = create_access_token("user-id")
    assert decode_token(token, "access")["sub"] == "user-id"


def test_refresh_token_is_not_an_access_token() -> None:
    with pytest.raises(jwt.InvalidTokenError):
        decode_token(create_refresh_token("user-id"), "access")
