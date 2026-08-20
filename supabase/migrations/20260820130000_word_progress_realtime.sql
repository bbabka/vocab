-- Extend Realtime delivery to word_progress, same as
-- 20260721190000_realtime_publication.sql did for words/collections/
-- daily_activity. RLS continues to scope delivery per-row to each row's
-- own user_id.
alter publication supabase_realtime add table word_progress;
