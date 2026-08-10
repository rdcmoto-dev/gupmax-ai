"""Create prompts.

Revision ID: 0003_prompts
Revises: 0002_auth_roles
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0003_prompts"
down_revision: str | None = "0002_auth_roles"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "prompts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("original_input", sa.Text(), nullable=False),
        sa.Column("generated_prompt", sa.Text(), nullable=False),
        sa.Column("category", sa.String(length=40), nullable=False),
        sa.Column("language", sa.String(length=20), nullable=False),
        sa.Column("tone", sa.String(length=80), nullable=True),
        sa.Column("mode", sa.String(length=20), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("provider", sa.String(length=50), nullable=True),
        sa.Column("model", sa.String(length=200), nullable=True),
        sa.Column("input_tokens", sa.Integer(), nullable=True),
        sa.Column("output_tokens", sa.Integer(), nullable=True),
        sa.Column("total_tokens", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_prompts_user_id"), "prompts", ["user_id"], unique=False)
    op.create_index(op.f("ix_prompts_category"), "prompts", ["category"], unique=False)
    op.create_index(op.f("ix_prompts_language"), "prompts", ["language"], unique=False)
    op.create_index(op.f("ix_prompts_mode"), "prompts", ["mode"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_prompts_mode"), table_name="prompts")
    op.drop_index(op.f("ix_prompts_language"), table_name="prompts")
    op.drop_index(op.f("ix_prompts_category"), table_name="prompts")
    op.drop_index(op.f("ix_prompts_user_id"), table_name="prompts")
    op.drop_table("prompts")
