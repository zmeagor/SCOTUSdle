-- Run this if profiles + game_results already exist but the rest of schema.sql didn't finish.

-- ---------- streaks ----------
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
create table public.topic_completion (
  user_id uuid not null references public.profiles(id) on delete cascade,
  topic text not null,
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
create table public.subscriptions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  status text not null default 'inactive',
  plan text,
  current_period_end timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.subscriptions enable row level security;

create policy "subscriptions: select own" on public.subscriptions
  for select using (auth.uid() = user_id);
