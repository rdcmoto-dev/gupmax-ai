"""Add prompt generation idempotency.

Revision ID: 0009_prompt_idempotency
Revises: 0008_adaptive_interview_facts
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0009_prompt_idempotency"
down_revision: str | None = "0008_adaptive_interview_facts"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("prompts", sa.Column("idempotency_key", sa.String(200)))
    op.add_column("prompts", sa.Column("request_fingerprint", sa.String(64)))
    op.create_index("ix_prompts_idempotency_key", "prompts", ["idempotency_key"])
    op.create_unique_constraint("uq_prompts_user_idempotency_key", "prompts", ["user_id", "idempotency_key"])


def downgrade() -> None:
    op.drop_constraint("uq_prompts_user_idempotency_key", "prompts", type_="unique")
    op.drop_index("ix_prompts_idempotency_key", table_name="prompts")
    op.drop_column("prompts", "request_fingerprint")
    op.drop_column("prompts", "idempotency_key")
