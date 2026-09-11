"""Add the independent operational pin flag to projects.

Revision ID: 0019_project_pins
Revises: 0018_project_blueprints
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0019_project_pins"
down_revision: str | None = "0018_project_blueprints"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("projects", sa.Column("is_pinned", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.create_index("ix_projects_is_pinned", "projects", ["is_pinned"])


def downgrade() -> None:
    op.drop_index("ix_projects_is_pinned", table_name="projects")
    op.drop_column("projects", "is_pinned")
