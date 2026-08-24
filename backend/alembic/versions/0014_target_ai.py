"""Persist the target AI for prompts and templates.

Revision ID: 0014_target_ai
Revises: 0013_projects
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0014_target_ai"
down_revision: str | None = "0013_projects"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "prompts", sa.Column("target_ai", sa.String(40), nullable=False, server_default="generic")
    )
    op.create_index("ix_prompts_target_ai", "prompts", ["target_ai"])
    op.add_column(
        "prompt_templates", sa.Column("target_ai", sa.String(40), nullable=False, server_default="generic")
    )
    op.create_index("ix_prompt_templates_target_ai", "prompt_templates", ["target_ai"])


def downgrade() -> None:
    op.drop_index("ix_prompt_templates_target_ai", table_name="prompt_templates")
    op.drop_column("prompt_templates", "target_ai")
    op.drop_index("ix_prompts_target_ai", table_name="prompts")
    op.drop_column("prompts", "target_ai")
