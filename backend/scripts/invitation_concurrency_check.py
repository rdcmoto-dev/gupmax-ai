"""Exercise HTTP signup against a disposable PostgreSQL, never the configured database.

Requires the system identifier read directly from the dedicated test container.
Uses create_all only on an empty invitation_audit database; does not run migrations.
"""

import argparse
import asyncio
import json
from unittest.mock import patch

import asyncpg
import httpx
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine


async def main(system_identifier: str) -> None:
    dsn = "postgresql://postgres@127.0.0.1:55439/invitation_audit"
    probe = await asyncpg.connect(dsn, timeout=5)
    try:
        actual = await probe.fetchval("SELECT system_identifier::text FROM pg_control_system()")
        if actual != system_identifier:
            raise RuntimeError("Refusing database with unexpected system identifier")
        if await probe.fetchval("SELECT count(*) FROM information_schema.tables WHERE table_schema='public'"):
            raise RuntimeError("Refusing nonempty database")
    finally:
        await probe.close()

    from app.core.config import Settings

    settings = Settings(
        _env_file=None, database_url=dsn.replace("postgresql://", "postgresql+asyncpg://"),
        jwt_secret_key="isolated-invitation-test-signing-key-not-for-real-use",
        environment="test", openai_api_key=None, stripe_secret_key=None, mercado_pago_access_token=None,
    )
    with patch("app.core.config.get_settings", return_value=settings):
        from app.db.base import Base
        from app.db.session import get_db_session
        from app.main import app
        from app.modules.auth.service import AuthService
        from app.modules.billing.model import Subscription, UsageRecord
        from app.modules.credits.model import CreditReservation, CreditTransaction, CreditWallet
        from app.modules.users.model import User
        from app.modules.users.schemas import AdminUserCreate

        engine = create_async_engine(str(settings.database_url))
        factory = async_sessionmaker(engine, expire_on_commit=False)
        ready = asyncio.Event()
        connections: set[int] = set()
        racing = False

        async def isolated_session():
            async with factory() as session:
                if racing:
                    connections.add(await session.scalar(text("SELECT pg_backend_pid()")))
                    if len(connections) == 2:
                        ready.set()
                    await asyncio.wait_for(ready.wait(), timeout=10)
                yield session

        app.dependency_overrides[get_db_session] = isolated_session
        try:
            async with engine.begin() as connection:
                await connection.run_sync(Base.metadata.create_all)
            async with factory() as session:
                await AuthService(session).register(AdminUserCreate(
                    email="issuer@example.com", full_name="Isolated Administrator",
                    password="IsolatedPassword123!", role="admin",
                ))
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://isolated") as client:
                login = await client.post("/api/v1/auth/login", json={
                    "email": "issuer@example.com", "password": "IsolatedPassword123!",
                })
                assert login.status_code == 200
                issued = await client.post("/api/v1/auth/invitations", json={"email": "invitee@example.com"},
                                           headers={"Authorization": f"Bearer {login.json()['access_token']}"})
                assert issued.status_code == 201
                payload = {
                    "email": "invitee@example.com", "full_name": "Isolated Invitee",
                    "password": "IsolatedPassword123!", "invitation_token": issued.json()["invitation_token"],
                }
                # Both HTTP requests hold distinct PostgreSQL connections before proceeding.
                racing = True
                results = await asyncio.wait_for(asyncio.gather(
                    client.post("/api/v1/auth/register", json=payload),
                    client.post("/api/v1/auth/register", json=payload),
                ), timeout=30)
                racing = False
                statuses = sorted(response.status_code for response in results)
                assert statuses == [201, 403], statuses
                assert len(connections) == 2

            async with factory() as session:
                users = list((await session.scalars(select(User).where(User.email == "invitee@example.com"))).all())
                assert len(users) == 1
                uid = users[0].id
                trials = await session.scalar(select(func.count()).select_from(Subscription).where(
                    Subscription.user_id == uid, Subscription.status == "trialing",
                ))
                grants = list((await session.scalars(select(CreditTransaction).where(
                    CreditTransaction.user_id == uid,
                ))).all())
                wallet = await session.scalar(select(CreditWallet).where(CreditWallet.user_id == uid))
                assert trials == 1 and len(grants) == 1
                assert grants[0].type == "trial_grant" and grants[0].amount == 100
                assert wallet.available_balance == 100 and wallet.reserved_balance == 0
                for model in (UsageRecord, CreditReservation):
                    assert await session.scalar(select(func.count()).select_from(model)) == 0
                print(json.dumps({"postgresql_connections": len(connections), "http_statuses": statuses,
                                  "accounts": len(users), "trials": trials, "initial_grants": len(grants),
                                  "credits": wallet.available_balance, "usage": 0, "reservations": 0}))
        finally:
            app.dependency_overrides.clear()
            await engine.dispose()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--system-identifier", required=True)
    asyncio.run(main(parser.parse_args().system_identifier))
