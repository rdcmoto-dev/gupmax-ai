# ruff: noqa: E501
"""Add credit wallet system.

Revision ID: 0005_credit_wallet
Revises: 0004_billing
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0005_credit_wallet"
down_revision: str | None = "0004_billing"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _timestamps() -> tuple[sa.Column, sa.Column]:
    return (
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )


def upgrade() -> None:
    op.add_column("plans", sa.Column("monthly_credit_grant", sa.Integer(), server_default="0", nullable=False))
    op.create_check_constraint("ck_plans_credit_grant_nonnegative", "plans", "monthly_credit_grant >= 0")
    op.execute(
        "UPDATE plans SET monthly_credit_grant = CASE code WHEN 'STARTER' THEN 500 WHEN 'PRO' THEN 2000 WHEN 'BUSINESS' THEN 10000 ELSE 0 END"
    )

    op.create_table(
        "credit_wallets",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("available_balance", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column("reserved_balance", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column("lifetime_credited", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column("lifetime_spent", sa.BigInteger(), server_default="0", nullable=False),
        *_timestamps(),
        sa.CheckConstraint("available_balance >= 0", name="ck_wallet_available_nonnegative"),
        sa.CheckConstraint("reserved_balance >= 0", name="ck_wallet_reserved_nonnegative"),
        sa.CheckConstraint("lifetime_credited >= 0", name="ck_wallet_credited_nonnegative"),
        sa.CheckConstraint("lifetime_spent >= 0", name="ck_wallet_spent_nonnegative"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id"),
    )
    op.create_index(op.f("ix_credit_wallets_user_id"), "credit_wallets", ["user_id"], unique=True)

    op.create_table(
        "credit_lots",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("wallet_id", sa.Uuid(), nullable=False),
        sa.Column("source", sa.String(20), nullable=False),
        sa.Column("original_amount", sa.BigInteger(), nullable=False),
        sa.Column("available_amount", sa.BigInteger(), nullable=False),
        sa.Column("reserved_amount", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint("original_amount > 0", name="ck_credit_lot_original_positive"),
        sa.CheckConstraint("available_amount >= 0", name="ck_credit_lot_available_nonnegative"),
        sa.CheckConstraint("reserved_amount >= 0", name="ck_credit_lot_reserved_nonnegative"),
        sa.ForeignKeyConstraint(["wallet_id"], ["credit_wallets.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_credit_lots_wallet_id"), "credit_lots", ["wallet_id"])
    op.create_index(op.f("ix_credit_lots_expires_at"), "credit_lots", ["expires_at"])

    op.create_table(
        "credit_transactions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("wallet_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("type", sa.String(30), nullable=False),
        sa.Column("amount", sa.BigInteger(), nullable=False),
        sa.Column("balance_after", sa.BigInteger(), nullable=False),
        sa.Column("reference_type", sa.String(50), nullable=False),
        sa.Column("reference_id", sa.String(255), nullable=False),
        sa.Column("idempotency_key", sa.String(255), nullable=False),
        sa.Column("description", sa.String(500), nullable=False),
        sa.Column("metadata", sa.JSON()),
        sa.Column("expires_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint("balance_after >= 0", name="ck_credit_transaction_balance_nonnegative"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["wallet_id"], ["credit_wallets.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("idempotency_key"),
    )
    op.create_index(op.f("ix_credit_transactions_wallet_id"), "credit_transactions", ["wallet_id"])
    op.create_index(op.f("ix_credit_transactions_user_id"), "credit_transactions", ["user_id"])
    op.create_index(
        op.f("ix_credit_transactions_idempotency_key"), "credit_transactions", ["idempotency_key"], unique=True
    )
    op.create_index(op.f("ix_credit_transactions_created_at"), "credit_transactions", ["created_at"])

    op.create_table(
        "credit_reservations",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("wallet_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("operation_type", sa.String(40), nullable=False),
        sa.Column("idempotency_key", sa.String(255), nullable=False),
        sa.Column("reserved_credits", sa.BigInteger(), nullable=False),
        sa.Column("settled_credits", sa.BigInteger()),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("settled_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint("reserved_credits > 0", name="ck_credit_reservation_positive"),
        sa.CheckConstraint("settled_credits IS NULL OR settled_credits >= 0", name="ck_credit_settlement_nonnegative"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["wallet_id"], ["credit_wallets.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("idempotency_key"),
    )
    op.create_index(op.f("ix_credit_reservations_wallet_id"), "credit_reservations", ["wallet_id"])
    op.create_index(op.f("ix_credit_reservations_user_id"), "credit_reservations", ["user_id"])
    op.create_index(
        op.f("ix_credit_reservations_idempotency_key"), "credit_reservations", ["idempotency_key"], unique=True
    )

    op.create_table(
        "credit_reservation_allocations",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("reservation_id", sa.Uuid(), nullable=False),
        sa.Column("lot_id", sa.Uuid(), nullable=False),
        sa.Column("amount", sa.BigInteger(), nullable=False),
        sa.CheckConstraint("amount > 0", name="ck_credit_allocation_positive"),
        sa.ForeignKeyConstraint(["lot_id"], ["credit_lots.id"]),
        sa.ForeignKeyConstraint(["reservation_id"], ["credit_reservations.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_credit_reservation_allocations_lot_id"), "credit_reservation_allocations", ["lot_id"])
    op.create_index(
        op.f("ix_credit_reservation_allocations_reservation_id"), "credit_reservation_allocations", ["reservation_id"]
    )

    op.create_table(
        "credit_packages",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("code", sa.String(50), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("credits", sa.BigInteger(), nullable=False),
        sa.Column("price", sa.Numeric(12, 2), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False),
        sa.Column("bonus_credits", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("sort_order", sa.Integer(), server_default="0", nullable=False),
        *_timestamps(),
        sa.CheckConstraint("credits > 0", name="ck_credit_package_credits_positive"),
        sa.CheckConstraint("bonus_credits >= 0", name="ck_credit_package_bonus_nonnegative"),
        sa.CheckConstraint("price >= 0", name="ck_credit_package_price_nonnegative"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("code"),
    )
    op.create_index(op.f("ix_credit_packages_code"), "credit_packages", ["code"], unique=True)

    op.create_table(
        "credit_cost_rules",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("operation_type", sa.String(40), nullable=False),
        sa.Column("provider", sa.String(50), nullable=False),
        sa.Column("model", sa.String(200)),
        sa.Column("base_credit_cost", sa.Integer(), nullable=False),
        sa.Column("input_token_rate", sa.Numeric(12, 6), nullable=False),
        sa.Column("output_token_rate", sa.Numeric(12, 6), nullable=False),
        sa.Column("minimum_credit_cost", sa.Integer(), nullable=False),
        sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=False),
        *_timestamps(),
        sa.CheckConstraint("base_credit_cost >= 0", name="ck_credit_cost_base_nonnegative"),
        sa.CheckConstraint("input_token_rate >= 0", name="ck_credit_cost_input_nonnegative"),
        sa.CheckConstraint("output_token_rate >= 0", name="ck_credit_cost_output_nonnegative"),
        sa.CheckConstraint("minimum_credit_cost >= 0", name="ck_credit_cost_minimum_nonnegative"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_credit_cost_rules_operation_type"), "credit_cost_rules", ["operation_type"])
    op.create_index("uq_credit_cost_rule", "credit_cost_rules", ["operation_type", "provider", "model"], unique=True)

    op.execute(
        sa.text("""
        INSERT INTO credit_packages (id, code, name, credits, price, currency, bonus_credits, is_active, sort_order)
        VALUES
        ('20000000-0000-0000-0000-000000000001', 'CREDITS_500', '500 créditos', 500, 19.90, 'BRL', 0, true, 10),
        ('20000000-0000-0000-0000-000000000002', 'CREDITS_1500', '1.500 créditos', 1500, 49.90, 'BRL', 100, true, 20),
        ('20000000-0000-0000-0000-000000000003', 'CREDITS_5000', '5.000 créditos', 5000, 149.90, 'BRL', 500, true, 30),
        ('20000000-0000-0000-0000-000000000004', 'CREDITS_10000', '10.000 créditos', 10000, 269.90, 'BRL', 1500, true, 40)
        ON CONFLICT (code) DO NOTHING
    """)
    )
    op.execute(
        sa.text("""
        INSERT INTO credit_cost_rules (
            id, operation_type, provider, model, base_credit_cost, input_token_rate,
            output_token_rate, minimum_credit_cost, is_active
        ) VALUES
        ('30000000-0000-0000-0000-000000000001', 'prompt_optimization', 'openai', NULL, 1, 0.001, 0.002, 1, true),
        ('30000000-0000-0000-0000-000000000002', 'text_generation', 'openai', NULL, 1, 0.001, 0.002, 1, true)
    """)
    )
    op.execute(
        "INSERT INTO credit_wallets (id, user_id) SELECT gen_random_uuid(), id FROM users ON CONFLICT (user_id) DO NOTHING"
    )
    op.execute(
        sa.text("""
        WITH eligible AS (
            SELECT w.id AS wallet_id, w.user_id, s.id AS subscription_id, s.trial_ends_at
            FROM credit_wallets w JOIN subscriptions s ON s.user_id = w.user_id
            WHERE s.trial_ends_at > now()
        ), inserted_lots AS (
            INSERT INTO credit_lots (id, wallet_id, source, original_amount, available_amount, reserved_amount, expires_at)
            SELECT gen_random_uuid(), wallet_id, 'trial', 100, 100, 0, trial_ends_at FROM eligible
            RETURNING wallet_id
        )
        UPDATE credit_wallets SET available_balance = 100, lifetime_credited = 100
        WHERE id IN (SELECT wallet_id FROM inserted_lots)
    """)
    )
    op.execute(
        sa.text("""
        INSERT INTO credit_transactions (
            id, wallet_id, user_id, type, amount, balance_after, reference_type,
            reference_id, idempotency_key, description, expires_at
        )
        SELECT gen_random_uuid(), w.id, w.user_id, 'trial_grant', 100, 100, 'subscription_trial',
               s.id::text, 'trial:' || s.id::text, 'Trial credit grant', s.trial_ends_at
        FROM credit_wallets w JOIN subscriptions s ON s.user_id = w.user_id
        WHERE s.trial_ends_at > now()
        ON CONFLICT (idempotency_key) DO NOTHING
    """)
    )


def downgrade() -> None:
    op.drop_index("uq_credit_cost_rule", table_name="credit_cost_rules")
    op.drop_index(op.f("ix_credit_cost_rules_operation_type"), table_name="credit_cost_rules")
    op.drop_table("credit_cost_rules")
    op.drop_index(op.f("ix_credit_packages_code"), table_name="credit_packages")
    op.drop_table("credit_packages")
    op.drop_index(op.f("ix_credit_reservation_allocations_reservation_id"), table_name="credit_reservation_allocations")
    op.drop_index(op.f("ix_credit_reservation_allocations_lot_id"), table_name="credit_reservation_allocations")
    op.drop_table("credit_reservation_allocations")
    op.drop_index(op.f("ix_credit_reservations_idempotency_key"), table_name="credit_reservations")
    op.drop_index(op.f("ix_credit_reservations_user_id"), table_name="credit_reservations")
    op.drop_index(op.f("ix_credit_reservations_wallet_id"), table_name="credit_reservations")
    op.drop_table("credit_reservations")
    op.drop_index(op.f("ix_credit_transactions_created_at"), table_name="credit_transactions")
    op.drop_index(op.f("ix_credit_transactions_idempotency_key"), table_name="credit_transactions")
    op.drop_index(op.f("ix_credit_transactions_user_id"), table_name="credit_transactions")
    op.drop_index(op.f("ix_credit_transactions_wallet_id"), table_name="credit_transactions")
    op.drop_table("credit_transactions")
    op.drop_index(op.f("ix_credit_lots_expires_at"), table_name="credit_lots")
    op.drop_index(op.f("ix_credit_lots_wallet_id"), table_name="credit_lots")
    op.drop_table("credit_lots")
    op.drop_index(op.f("ix_credit_wallets_user_id"), table_name="credit_wallets")
    op.drop_table("credit_wallets")
    op.drop_constraint("ck_plans_credit_grant_nonnegative", "plans", type_="check")
    op.drop_column("plans", "monthly_credit_grant")
