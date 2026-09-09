"""Persist project favorites without modifying project activity dates.

Revision ID: 0017_project_favorites
Revises: 0016_guided_chain_execution
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0017_project_favorites"
down_revision: str | None = "0016_guided_chain_execution"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("projects", sa.Column("is_favorite", sa.Boolean(), nullable=False, server_default=sa.false()))


def downgrade() -> None:
    op.drop_column("projects", "is_favorite")
