"""Create intelligent interview sessions and answers.

Revision ID: 0007_interviews
Revises: 0006_payments
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0007_interviews"
down_revision: str | None = "0006_payments"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "interview_sessions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("mode", sa.String(20), nullable=False),
        sa.Column("category", sa.String(40), nullable=False),
        sa.Column("initial_request", sa.Text(), nullable=False),
        sa.Column("questions", sa.JSON(), nullable=False),
        sa.Column("structured_prompt", sa.JSON()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True)),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_interview_sessions_user_id"), "interview_sessions", ["user_id"])
    op.create_index(op.f("ix_interview_sessions_status"), "interview_sessions", ["status"])
    op.create_index(op.f("ix_interview_sessions_mode"), "interview_sessions", ["mode"])
    op.create_index(op.f("ix_interview_sessions_category"), "interview_sessions", ["category"])
    op.create_index(op.f("ix_interview_sessions_expires_at"), "interview_sessions", ["expires_at"])

    op.create_table(
        "interview_answers",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("interview_id", sa.Uuid(), nullable=False),
        sa.Column("question_key", sa.String(64), nullable=False),
        sa.Column("value", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["interview_id"], ["interview_sessions.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("interview_id", "question_key", name="uq_interview_answers_question"),
    )
    op.create_index(op.f("ix_interview_answers_interview_id"), "interview_answers", ["interview_id"])


def downgrade() -> None:
    op.drop_index(op.f("ix_interview_answers_interview_id"), table_name="interview_answers")
    op.drop_table("interview_answers")
    op.drop_index(op.f("ix_interview_sessions_expires_at"), table_name="interview_sessions")
    op.drop_index(op.f("ix_interview_sessions_category"), table_name="interview_sessions")
    op.drop_index(op.f("ix_interview_sessions_mode"), table_name="interview_sessions")
    op.drop_index(op.f("ix_interview_sessions_status"), table_name="interview_sessions")
    op.drop_index(op.f("ix_interview_sessions_user_id"), table_name="interview_sessions")
    op.drop_table("interview_sessions")
