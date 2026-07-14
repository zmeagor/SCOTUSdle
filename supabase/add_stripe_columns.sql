alter table public.subscriptions
  add column if not exists stripe_customer_id text unique,
  add column if not exists stripe_subscription_id text unique;
