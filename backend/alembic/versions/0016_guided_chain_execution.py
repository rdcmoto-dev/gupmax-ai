"""Add persistent guided execution state to prompt chain steps.

Revision ID: 0016_guided_chain_execution
Revises: 0015_prompt_chains
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0016_guided_chain_execution"
down_revision: str | None = "0015_prompt_chains"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "prompt_chain_steps",
        sa.Column("execution_status", sa.String(length=20), nullable=False, server_default="pending"),
    )
    op.add_column("prompt_chain_steps", sa.Column("result", sa.Text(), nullable=True))
    op.add_column(
        "prompt_chain_steps", sa.Column("started_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "prompt_chain_steps", sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.create_index(
        "ix_prompt_chain_steps_execution_status",
        "prompt_chain_steps",
        ["execution_status"],
    )
    op.alter_column("prompt_chain_steps", "execution_status", server_default=None)


def downgrade() -> None:
    op.drop_index("ix_prompt_chain_steps_execution_status", table_name="prompt_chain_steps")
    op.drop_column("prompt_chain_steps", "completed_at")
    op.drop_column("prompt_chain_steps", "started_at")
    op.drop_column("prompt_chain_steps", "result")
    op.drop_column("prompt_chain_steps", "execution_status")
