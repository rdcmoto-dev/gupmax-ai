"""Add private prompt templates.

Revision ID: 0012_prompt_templates
Revises: 0011_smart_profile
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0012_prompt_templates"
down_revision: str | None = "0011_smart_profile"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "prompt_templates",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("source_prompt_id", sa.Uuid(), sa.ForeignKey("prompts.id", ondelete="SET NULL")),
        sa.Column("name", sa.String(160), nullable=False),
        sa.Column("description", sa.String(1000)),
        sa.Column("category", sa.String(40), nullable=False),
        sa.Column("mode", sa.String(20), nullable=False),
        sa.Column("template_content", sa.Text(), nullable=False),
        sa.Column("base_input", sa.Text(), nullable=False),
        sa.Column("language", sa.String(20), nullable=False, server_default="pt-BR"),
        sa.Column("tone", sa.String(80)),
        sa.Column("audience", sa.String(1000)),
        sa.Column("context", sa.Text()),
        sa.Column("output_format", sa.String(1000)),
        sa.Column("constraints", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("instructions", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("additional_information", sa.String(2000)),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_prompt_templates_user_id", "prompt_templates", ["user_id"])
    op.create_index("ix_prompt_templates_source_prompt_id", "prompt_templates", ["source_prompt_id"])
    op.create_index("ix_prompt_templates_category", "prompt_templates", ["category"])
    op.create_index("ix_prompt_templates_mode", "prompt_templates", ["mode"])


def downgrade() -> None:
    op.drop_index("ix_prompt_templates_mode", table_name="prompt_templates")
    op.drop_index("ix_prompt_templates_category", table_name="prompt_templates")
    op.drop_index("ix_prompt_templates_source_prompt_id", table_name="prompt_templates")
    op.drop_index("ix_prompt_templates_user_id", table_name="prompt_templates")
    op.drop_table("prompt_templates")
