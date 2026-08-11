"""Validate credit double-spend protection against the configured PostgreSQL."""

import asyncio
from uuid import uuid4

from sqlalchemy import delete

from app.db.session import SessionLocal
from app.modules.credits.enums import CreditOperationType, CreditSource, CreditTransactionType
from app.modules.credits.exceptions import InsufficientCredits
from app.modules.credits.service import CreditService
from app.modules.users.model import User


async def reserve_once(user_id, key: str) -> str:
    async with SessionLocal() as session:
        try:
            await CreditService(session).reserve(
                user_id,
                CreditOperationType.PROMPT_OPTIMIZATION,
                "openai",
                None,
                0,
                0,
                key,
            )
            return "reserved"
        except InsufficientCredits:
            return "blocked"


async def main() -> None:
    marker = uuid4()
    async with SessionLocal() as session:
        user = User(
            id=marker,
            email=f"credit-concurrency-{marker}@example.invalid",
            full_name="Credit Concurrency Check",
            hashed_password="not-a-login-account",
        )
        session.add(user)
        await session.commit()
        await CreditService(session).grant(
            user.id,
            1,
            source=CreditSource.PROMOTIONAL,
            transaction_type=CreditTransactionType.PROMOTION,
            reference_type="validation",
            reference_id=str(marker),
            idempotency_key=f"validation-grant:{marker}",
            description="Temporary concurrency validation credit",
        )
    try:
        results = await asyncio.gather(
            reserve_once(marker, f"validation-reserve-a:{marker}"),
            reserve_once(marker, f"validation-reserve-b:{marker}"),
        )
        print(f"reserved={results.count('reserved')} blocked={results.count('blocked')}")
        if sorted(results) != ["blocked", "reserved"]:
            raise RuntimeError("double-spend protection validation failed")
    finally:
        async with SessionLocal() as session:
            await session.execute(delete(User).where(User.id == marker))
            await session.commit()


if __name__ == "__main__":
    asyncio.run(main())
