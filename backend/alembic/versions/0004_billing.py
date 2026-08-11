"""Add billing, subscriptions and usage.

Revision ID: 0004_billing
Revises: 0003_prompts
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0004_billing"
down_revision: str | None = "0003_prompts"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "plans",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("code", sa.String(40), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("price", sa.Numeric(12, 2), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False),
        sa.Column("billing_interval", sa.String(20), nullable=False),
        sa.Column("trial_days", sa.Integer(), nullable=False),
        sa.Column("monthly_generation_limit", sa.Integer(), nullable=False),
        sa.Column("monthly_input_token_limit", sa.Integer(), nullable=False),
        sa.Column("monthly_output_token_limit", sa.Integer(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint("price >= 0", name="ck_plans_price_nonnegative"),
        sa.CheckConstraint("trial_days >= 0", name="ck_plans_trial_days_nonnegative"),
        sa.CheckConstraint("monthly_generation_limit >= 0", name="ck_plans_generation_limit_nonnegative"),
        sa.CheckConstraint("monthly_input_token_limit >= 0", name="ck_plans_input_limit_nonnegative"),
        sa.CheckConstraint("monthly_output_token_limit >= 0", name="ck_plans_output_limit_nonnegative"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("code"),
    )
    op.create_index(op.f("ix_plans_code"), "plans", ["code"], unique=True)
    op.create_table(
        "subscriptions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("plan_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("provider", sa.String(30), nullable=False),
        sa.Column("provider_customer_id", sa.String(255)),
        sa.Column("provider_subscription_id", sa.String(255)),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("current_period_start", sa.DateTime(timezone=True), nullable=False),
        sa.Column("current_period_end", sa.DateTime(timezone=True), nullable=False),
        sa.Column("cancel_at_period_end", sa.Boolean(), nullable=False),
        sa.Column("canceled_at", sa.DateTime(timezone=True)),
        sa.Column("trial_started_at", sa.DateTime(timezone=True)),
        sa.Column("trial_ends_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["plan_id"], ["plans.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id"),
    )
    op.create_index(op.f("ix_subscriptions_plan_id"), "subscriptions", ["plan_id"])
    op.create_index(op.f("ix_subscriptions_user_id"), "subscriptions", ["user_id"], unique=True)
    op.create_table(
        "usage_records",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("prompt_id", sa.Uuid()),
        sa.Column("provider", sa.String(50), nullable=False),
        sa.Column("model", sa.String(200)),
        sa.Column("input_tokens", sa.Integer(), nullable=False),
        sa.Column("output_tokens", sa.Integer(), nullable=False),
        sa.Column("total_tokens", sa.Integer(), nullable=False),
        sa.Column("generation_count", sa.Integer(), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.CheckConstraint("input_tokens >= 0", name="ck_usage_input_nonnegative"),
        sa.CheckConstraint("output_tokens >= 0", name="ck_usage_output_nonnegative"),
        sa.CheckConstraint("total_tokens >= 0", name="ck_usage_total_nonnegative"),
        sa.CheckConstraint("generation_count >= 0", name="ck_usage_generation_nonnegative"),
        sa.ForeignKeyConstraint(["prompt_id"], ["prompts.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_usage_records_occurred_at"), "usage_records", ["occurred_at"])
    op.create_index(op.f("ix_usage_records_prompt_id"), "usage_records", ["prompt_id"])
    op.create_index(op.f("ix_usage_records_user_id"), "usage_records", ["user_id"])

    op.execute(
        sa.text("""
        INSERT INTO plans (
            id, code, name, description, price, currency, billing_interval, trial_days,
            monthly_generation_limit, monthly_input_token_limit, monthly_output_token_limit, is_active
        ) VALUES
        (
            '10000000-0000-0000-0000-000000000001', 'FREE', 'Free',
            'Uso básico sem otimização por IA.', 0, 'BRL', 'month', 0, 0, 0, 0, true
        ),
        (
            '10000000-0000-0000-0000-000000000002', 'STARTER', 'Starter',
            'Plano inicial para uso individual.', 29.90, 'BRL', 'month', 5, 100, 100000, 40000, true
        ),
        (
            '10000000-0000-0000-0000-000000000003', 'PRO', 'Pro',
            'Limites ampliados para uso profissional.', 79.90, 'BRL', 'month', 5, 1000, 500000, 200000, true
        ),
        (
            '10000000-0000-0000-0000-000000000004', 'BUSINESS', 'Business',
            'Capacidade para equipes e alto volume.', 249.90, 'BRL', 'month', 5, 5000, 3000000, 1000000, true
        )
        ON CONFLICT (code) DO NOTHING
    """)
    )
    op.execute(
        sa.text("""
        INSERT INTO subscriptions (
            id, user_id, plan_id, status, provider, started_at, current_period_start,
            current_period_end, cancel_at_period_end, trial_started_at, trial_ends_at
        )
        SELECT gen_random_uuid(), users.id, plans.id, 'trialing', 'internal', now(), now(),
               now() + interval '5 days', false, now(), now() + interval '5 days'
        FROM users CROSS JOIN plans
        WHERE plans.code = 'STARTER'
        ON CONFLICT (user_id) DO NOTHING
    """)
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_usage_records_user_id"), table_name="usage_records")
    op.drop_index(op.f("ix_usage_records_prompt_id"), table_name="usage_records")
    op.drop_index(op.f("ix_usage_records_occurred_at"), table_name="usage_records")
    op.drop_table("usage_records")
    op.drop_index(op.f("ix_subscriptions_user_id"), table_name="subscriptions")
    op.drop_index(op.f("ix_subscriptions_plan_id"), table_name="subscriptions")
    op.drop_table("subscriptions")
    op.drop_index(op.f("ix_plans_code"), table_name="plans")
    op.drop_table("plans")
