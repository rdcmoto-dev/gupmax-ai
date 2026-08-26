"""Create private prompt chains and ordered steps.

Revision ID: 0015_prompt_chains
Revises: 0014_target_ai
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0015_prompt_chains"
down_revision: str | None = "0014_target_ai"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "prompt_chains",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("project_id", sa.Uuid(), sa.ForeignKey("projects.id", ondelete="SET NULL")),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("description", sa.String(1000)),
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_prompt_chains_user_id", "prompt_chains", ["user_id"])
    op.create_index("ix_prompt_chains_project_id", "prompt_chains", ["project_id"])
    op.create_index("ix_prompt_chains_status", "prompt_chains", ["status"])
    op.create_table(
        "prompt_chain_steps",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("chain_id", sa.Uuid(), sa.ForeignKey("prompt_chains.id", ondelete="CASCADE"), nullable=False),
        sa.Column("template_id", sa.Uuid(), sa.ForeignKey("prompt_templates.id", ondelete="SET NULL")),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("base_input", sa.Text(), nullable=False),
        sa.Column("mode", sa.String(20), nullable=False),
        sa.Column("category", sa.String(40), nullable=False),
        sa.Column("target_ai", sa.String(40), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("chain_id", "position", name="uq_chain_step_position"),
    )
    op.create_index("ix_prompt_chain_steps_chain_id", "prompt_chain_steps", ["chain_id"])
    op.create_index("ix_prompt_chain_steps_template_id", "prompt_chain_steps", ["template_id"])


def downgrade() -> None:
    op.drop_table("prompt_chain_steps")
    op.drop_table("prompt_chains")
