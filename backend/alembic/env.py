import asyncio
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context
from app.core.config import get_settings
from app.db.base import Base
from app.modules.auth.model import PasswordResetToken, RefreshToken  # noqa: F401
from app.modules.billing.model import Plan, Subscription, UsageRecord  # noqa: F401
from app.modules.credits.model import (  # noqa: F401
    CreditCostRule,
    CreditLot,
    CreditPackage,
    CreditReservation,
    CreditReservationAllocation,
    CreditTransaction,
    CreditWallet,
)
from app.modules.interviews.model import InterviewAnswer, InterviewSession  # noqa: F401
from app.modules.payments.model import Payment, PaymentEvent  # noqa: F401
from app.modules.projects.model import Project  # noqa: F401
from app.modules.prompt_engine.model import Prompt  # noqa: F401
from app.modules.prompt_templates.model import PromptTemplate  # noqa: F401
from app.modules.smart_profile.model import UserPromptPreferences  # noqa: F401
from app.modules.users.model import User  # noqa: F401

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(url=str(get_settings().database_url), target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    configuration = config.get_section(config.config_ini_section, {})
    configuration["sqlalchemy.url"] = str(get_settings().database_url)
    connectable = async_engine_from_config(configuration, prefix="sqlalchemy.", poolclass=pool.NullPool)
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
