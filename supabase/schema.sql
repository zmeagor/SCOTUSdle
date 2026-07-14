-- SCOTUSdle Supabase schema
-- Run this in the Supabase SQL editor (Dashboard > SQL Editor > New query).
-- Auth users live in the built-in auth.users table; everything here references it.

-- ---------- profiles ----------
-- One row per user, created automatically on signup via trigger below.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles: select own" on public.profiles
  for select using (auth.uid() = id);

create policy "profiles: update own" on public.profiles
  for update using (auth.uid() = id);

-- auto-create a profile row whenever a new auth user signs up
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- ---------- game_results ----------
-- One row per (user, mode, day/case) result. Mirrors the old `history.results` map.
create table public.game_results (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  result_key text not null,        -- e.g. "daily-812", "archive-45", "property-<case name>"
  mode text not null,               -- "daily" | "archive" | "property" | "corporate" | "justicedle" | ...
  day_number int,                   -- null for bonus/non-daily-numbered rounds
  won boolean not null,
  clues_used int not null,
  is_daily_flow boolean not null default false,
  played_at timestamptz not null default now(),
  unique (user_id, result_key)
);

alter table public.game_results enable row level security;

create policy "game_results: select own" on public.game_results
  for select using (auth.uid() = user_id);

create policy "game_results: insert own" on public.game_results
  for insert with check (auth.uid() = user_id);

create index game_results_user_idx on public.game_results (user_id);


-- ---------- streaks ----------
-- One row per user; replaces history.currentStreak / maxStreak / lastPlayedDay.
create table public.streaks (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  current_streak int not null default 0,
  max_streak int not null default 0,
  last_played_day int,
  updated_at timestamptz not null default now()
);

alter table public.streaks enable row level security;

create policy "streaks: select own" on public.streaks
  for select using (auth.uid() = user_id);

create policy "streaks: upsert own" on public.streaks
  for insert with check (auth.uid() = user_id);

create policy "streaks: update own" on public.streaks
  for update using (auth.uid() = user_id);


-- ---------- topic_completion ----------
-- Replaces the `completion` object: which cases a user has seen per topic, plus play count.
create table public.topic_completion (
  user_id uuid not null references public.profiles(id) on delete cascade,
  topic text not null,               -- "property" | "corporate" | "justicedle" | "doctrinedle" | "criminaldle" | "tortsdle"
  total_plays int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, topic)
);

alter table public.topic_completion enable row level security;

create policy "topic_completion: select own" on public.topic_completion
  for select using (auth.uid() = user_id);

create policy "topic_completion: upsert own" on public.topic_completion
  for insert with check (auth.uid() = user_id);

create policy "topic_completion: update own" on public.topic_completion
  for update using (auth.uid() = user_id);

-- individual "seen" cases per topic (normalized instead of a JSON array)
create table public.topic_completion_seen (
  user_id uuid not null references public.profiles(id) on delete cascade,
  topic text not null,
  case_name text not null,
  seen_at timestamptz not null default now(),
  primary key (user_id, topic, case_name)
);

alter table public.topic_completion_seen enable row level security;

create policy "topic_completion_seen: select own" on public.topic_completion_seen
  for select using (auth.uid() = user_id);

create policy "topic_completion_seen: insert own" on public.topic_completion_seen
  for insert with check (auth.uid() = user_id);


-- ---------- archive_usage ----------
-- Replaces the `usage` { day, count } object (free-tier archive-play cap).
create table public.archive_usage (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day_number int not null,
  count int not null default 0,
  primary key (user_id, day_number)
);

alter table public.archive_usage enable row level security;

create policy "archive_usage: select own" on public.archive_usage
  for select using (auth.uid() = user_id);

create policy "archive_usage: upsert own" on public.archive_usage
  for insert with check (auth.uid() = user_id);

create policy "archive_usage: update own" on public.archive_usage
  for update using (auth.uid() = user_id);


-- ---------- subscriptions ----------
-- Replaces the `isSubscribed` boolean. Kept separate from profiles since it will
-- eventually be written by a server-side webhook (Stripe etc.), not the client.
create table public.subscriptions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  status text not null default 'inactive',  -- 'inactive' | 'active' | 'trialing' | 'past_due' | 'canceled'
  plan text,
  stripe_customer_id text unique,
  stripe_subscription_id text unique,
  current_period_end timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.subscriptions enable row level security;

-- Users can only READ their own subscription status. Writes happen only via
-- service_role (a Stripe webhook / Edge Function), never from the client,
-- so there is intentionally no insert/update policy for regular users here.
create policy "subscriptions: select own" on public.subscriptions
  for select using (auth.uid() = user_id);


-- ---------- base table grants ----------
-- RLS policies above only restrict *which rows* a query can see/touch; Postgres
-- separately requires the role to be granted access to the table at all. Some
-- Supabase projects don't have default privileges pre-configured on `public`,
-- so these are explicit here rather than assumed.
grant select, update on public.profiles to authenticated;
grant select, insert on public.game_results to authenticated;
grant select, insert, update on public.streaks to authenticated;
grant select, insert, update on public.topic_completion to authenticated;
grant select, insert on public.topic_completion_seen to authenticated;
grant select, insert, update on public.archive_usage to authenticated;
grant select on public.subscriptions to authenticated;
grant select, insert, update on public.subscriptions to service_role;
