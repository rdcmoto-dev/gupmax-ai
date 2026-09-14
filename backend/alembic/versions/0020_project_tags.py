"""Add project tags.
Revision ID: 0020_project_tags
Revises: 0019_project_pins
"""

import sqlalchemy as sa

from alembic import op

revision = "0020_project_tags"
down_revision = "0019_project_pins"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "project_tags",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(60), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("user_id", "name", name="uq_project_tags_user_name"),
    )
    op.create_index("ix_project_tags_user_id", "project_tags", ["user_id"])
    op.create_table(
        "project_tag_links",
        sa.Column("project_id", sa.Uuid(), sa.ForeignKey("projects.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("tag_id", sa.Uuid(), sa.ForeignKey("project_tags.id", ondelete="CASCADE"), primary_key=True),
    )


def downgrade():
    op.drop_table("project_tag_links")
    op.drop_index("ix_project_tags_user_id", table_name="project_tags")
    op.drop_table("project_tags")
