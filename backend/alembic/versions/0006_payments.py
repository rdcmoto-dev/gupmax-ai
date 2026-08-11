"""Add payments and webhook events.

Revision ID: 0006_payments
Revises: 0005_credit_wallet
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0006_payments"
down_revision: str | None = "0005_credit_wallet"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "payments",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("provider", sa.String(30), nullable=False),
        sa.Column("purpose", sa.String(30), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False),
        sa.Column("credit_package_id", sa.Uuid()),
        sa.Column("plan_id", sa.Uuid()),
        sa.Column("provider_payment_id", sa.String(255)),
        sa.Column("provider_checkout_id", sa.String(255)),
        sa.Column("checkout_url", sa.String(2048)),
        sa.Column("idempotency_key", sa.String(255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("paid_at", sa.DateTime(timezone=True)),
        sa.Column("canceled_at", sa.DateTime(timezone=True)),
        sa.Column("failed_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint("amount >= 0", name="ck_payments_amount_nonnegative"),
        sa.ForeignKeyConstraint(["credit_package_id"], ["credit_packages.id"]),
        sa.ForeignKeyConstraint(["plan_id"], ["plans.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("idempotency_key"),
    )
    op.create_index(op.f("ix_payments_user_id"), "payments", ["user_id"])
    op.create_index(op.f("ix_payments_provider_payment_id"), "payments", ["provider_payment_id"])
    op.create_index(op.f("ix_payments_provider_checkout_id"), "payments", ["provider_checkout_id"])
    op.create_index(op.f("ix_payments_idempotency_key"), "payments", ["idempotency_key"], unique=True)
    op.create_index(op.f("ix_payments_created_at"), "payments", ["created_at"])

    op.create_table(
        "payment_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("provider", sa.String(30), nullable=False),
        sa.Column("provider_event_id", sa.String(255), nullable=False),
        sa.Column("event_type", sa.String(100), nullable=False),
        sa.Column("payload_hash", sa.String(64), nullable=False),
        sa.Column("processing_status", sa.String(20), nullable=False),
        sa.Column("received_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("processed_at", sa.DateTime(timezone=True)),
        sa.Column("error_message", sa.String(500)),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("provider_event_id"),
    )
    op.create_index(op.f("ix_payment_events_provider_event_id"), "payment_events", ["provider_event_id"], unique=True)
    op.create_index(op.f("ix_payment_events_received_at"), "payment_events", ["received_at"])


def downgrade() -> None:
    op.drop_index(op.f("ix_payment_events_received_at"), table_name="payment_events")
    op.drop_index(op.f("ix_payment_events_provider_event_id"), table_name="payment_events")
    op.drop_table("payment_events")
    op.drop_index(op.f("ix_payments_created_at"), table_name="payments")
    op.drop_index(op.f("ix_payments_idempotency_key"), table_name="payments")
    op.drop_index(op.f("ix_payments_provider_checkout_id"), table_name="payments")
    op.drop_index(op.f("ix_payments_provider_payment_id"), table_name="payments")
    op.drop_index(op.f("ix_payments_user_id"), table_name="payments")
    op.drop_table("payments")
