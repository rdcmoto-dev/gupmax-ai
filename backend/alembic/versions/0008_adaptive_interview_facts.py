"""Persist structured facts for adaptive interviews.

Revision ID: 0008_adaptive_interview_facts
Revises: 0007_interviews
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0008_adaptive_interview_facts"
down_revision: str | None = "0007_interviews"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "interview_sessions",
        sa.Column("facts", sa.JSON(), server_default=sa.text("'{}'"), nullable=False),
    )


def downgrade() -> None:
    op.drop_column("interview_sessions", "facts")
