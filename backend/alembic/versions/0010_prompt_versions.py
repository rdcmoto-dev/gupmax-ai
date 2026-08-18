"""Add prompt version lineage.

Revision ID: 0010_prompt_versions
Revises: 0009_prompt_idempotency
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0010_prompt_versions"
down_revision: str | None = "0009_prompt_idempotency"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("prompts", sa.Column("parent_prompt_id", sa.Uuid()))
    op.add_column("prompts", sa.Column("root_prompt_id", sa.Uuid()))
    op.add_column("prompts", sa.Column("version_number", sa.Integer(), nullable=False, server_default="1"))
    op.add_column("prompts", sa.Column("refinement_instruction", sa.String(1000)))
    op.create_foreign_key(
        "fk_prompts_parent_prompt_id", "prompts", "prompts", ["parent_prompt_id"], ["id"], ondelete="SET NULL"
    )
    op.create_foreign_key(
        "fk_prompts_root_prompt_id", "prompts", "prompts", ["root_prompt_id"], ["id"], ondelete="SET NULL"
    )
    op.create_index("ix_prompts_parent_prompt_id", "prompts", ["parent_prompt_id"])
    op.create_index("ix_prompts_root_prompt_id", "prompts", ["root_prompt_id"])
    op.create_unique_constraint("uq_prompts_root_version", "prompts", ["root_prompt_id", "version_number"])
    op.alter_column("prompts", "version_number", server_default=None)


def downgrade() -> None:
    op.drop_constraint("uq_prompts_root_version", "prompts", type_="unique")
    op.drop_index("ix_prompts_root_prompt_id", table_name="prompts")
    op.drop_index("ix_prompts_parent_prompt_id", table_name="prompts")
    op.drop_constraint("fk_prompts_root_prompt_id", "prompts", type_="foreignkey")
    op.drop_constraint("fk_prompts_parent_prompt_id", "prompts", type_="foreignkey")
    op.drop_column("prompts", "refinement_instruction")
    op.drop_column("prompts", "version_number")
    op.drop_column("prompts", "root_prompt_id")
    op.drop_column("prompts", "parent_prompt_id")
