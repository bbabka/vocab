-- `daily_activity.user_id` was missing `default auth.uid()`, unlike
-- `collections`/`words`/`review_log`. The client never sends `user_id`
-- (server-defaulted, per the brief), so every insert landed as NULL and
-- failed its own RLS `WITH CHECK (user_id = auth.uid())` — caught live
-- while wiring Phase 3's `DailyActivityAPI.upsert`.
alter table daily_activity alter column user_id set default auth.uid();
