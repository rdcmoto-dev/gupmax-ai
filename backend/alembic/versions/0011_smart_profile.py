"""Add Smart Profile prompt preferences.

Revision ID: 0011_smart_profile
Revises: 0010_prompt_versions
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0011_smart_profile"
down_revision: str | None = "0010_prompt_versions"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "user_prompt_preferences",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("is_enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("default_language", sa.String(20)),
        sa.Column("default_tone", sa.String(80)),
        sa.Column("default_audience", sa.String(1000)),
        sa.Column("default_channel", sa.String(200)),
        sa.Column("default_output_format", sa.String(1000)),
        sa.Column("business_context", sa.Text()),
        sa.Column("default_constraints", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("default_instructions", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("user_id", name="uq_user_prompt_preferences_user_id"),
    )
    op.create_index("ix_user_prompt_preferences_user_id", "user_prompt_preferences", ["user_id"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_user_prompt_preferences_user_id", table_name="user_prompt_preferences")
    op.drop_table("user_prompt_preferences")
