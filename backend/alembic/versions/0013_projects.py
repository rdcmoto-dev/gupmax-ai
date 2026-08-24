"""Add private projects and optional associations.

Revision ID: 0013_projects
Revises: 0012_prompt_templates
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0013_projects"
down_revision: str | None = "0012_prompt_templates"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "projects",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(160), nullable=False),
        sa.Column("description", sa.String(1000)),
        sa.Column("context", sa.Text()),
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_projects_user_id", "projects", ["user_id"])
    op.create_index("ix_projects_status", "projects", ["status"])
    op.add_column("prompts", sa.Column("project_id", sa.Uuid()))
    op.create_foreign_key(
        "fk_prompts_project_id", "prompts", "projects", ["project_id"], ["id"], ondelete="SET NULL"
    )
    op.create_index("ix_prompts_project_id", "prompts", ["project_id"])
    op.add_column("prompt_templates", sa.Column("project_id", sa.Uuid()))
    op.create_foreign_key(
        "fk_prompt_templates_project_id", "prompt_templates", "projects", ["project_id"], ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_prompt_templates_project_id", "prompt_templates", ["project_id"])


def downgrade() -> None:
    op.drop_index("ix_prompt_templates_project_id", table_name="prompt_templates")
    op.drop_constraint("fk_prompt_templates_project_id", "prompt_templates", type_="foreignkey")
    op.drop_column("prompt_templates", "project_id")
    op.drop_index("ix_prompts_project_id", table_name="prompts")
    op.drop_constraint("fk_prompts_project_id", "prompts", type_="foreignkey")
    op.drop_column("prompts", "project_id")
    op.drop_index("ix_projects_status", table_name="projects")
    op.drop_index("ix_projects_user_id", table_name="projects")
    op.drop_table("projects")
