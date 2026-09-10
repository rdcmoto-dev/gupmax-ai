"""Add independent reusable project blueprints.

Revision ID: 0018_project_blueprints
Revises: 0017_project_favorites
"""

import sqlalchemy as sa

from alembic import op

revision = "0018_project_blueprints"
down_revision = "0017_project_favorites"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "project_blueprints",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(160), nullable=False),
        sa.Column("description", sa.String(1000)),
        sa.Column("category", sa.String(40), nullable=False),
        sa.Column("structure", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_project_blueprints_user_id", "project_blueprints", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_project_blueprints_user_id", table_name="project_blueprints")
    op.drop_table("project_blueprints")
