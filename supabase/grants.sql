-- Grants the base table privileges RLS needs to actually evaluate.
-- (RLS restricts rows; these GRANTs are the separate "can touch this table at all" layer.)

grant select, update on public.profiles to authenticated;

grant select, insert on public.game_results to authenticated;

grant select, insert, update on public.streaks to authenticated;

grant select, insert, update on public.topic_completion to authenticated;

grant select, insert on public.topic_completion_seen to authenticated;

grant select, insert, update on public.archive_usage to authenticated;

grant select on public.subscriptions to authenticated;
