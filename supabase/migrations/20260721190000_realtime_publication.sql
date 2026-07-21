-- Phase 5: add words/collections/daily_activity to the `supabase_realtime`
-- publication so `postgres_changes` events flow to subscribed clients.
-- `review_log` is deliberately excluded — it's write-mostly/online-only
-- (see ReviewStore's loadFromRemote comment) and isn't Realtime-subscribed.
-- RLS continues to scope delivery per-row to each row's own user_id, same
-- as any other authenticated request.
alter publication supabase_realtime add table collections, words, daily_activity;
