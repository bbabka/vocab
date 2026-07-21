-- Row Level Security: every table scoped to auth.uid(). Four explicit
-- policies per table (rather than one combined policy) so the USING vs.
-- WITH CHECK distinction stays reviewable — USING governs which existing
-- rows a command can see/target (select/update/delete), WITH CHECK governs
-- what a write is allowed to leave behind (insert/update). A policy with
-- only USING leaves INSERT unconstrained: a client could insert a row under
-- an arbitrary user_id.
--
-- Grants are separate from RLS and easy to forget: a table with RLS enabled
-- but no GRANT to `authenticated` is still unreachable via PostgREST
-- (auto_expose_new_tables defaults off). No grants to `anon` at all —
-- unauthenticated requests must fail outright, not merely be filtered out
-- by policy.

grant usage on schema public to authenticated;

alter table collections enable row level security;
alter table words enable row level security;
alter table review_log enable row level security;
alter table daily_activity enable row level security;

create policy collections_select on collections
    for select using (user_id = auth.uid());
create policy collections_insert on collections
    for insert with check (user_id = auth.uid());
create policy collections_update on collections
    for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy collections_delete on collections
    for delete using (user_id = auth.uid());

create policy words_select on words
    for select using (user_id = auth.uid());
create policy words_insert on words
    for insert with check (user_id = auth.uid());
create policy words_update on words
    for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy words_delete on words
    for delete using (user_id = auth.uid());

create policy review_log_select on review_log
    for select using (user_id = auth.uid());
create policy review_log_insert on review_log
    for insert with check (user_id = auth.uid());
create policy review_log_update on review_log
    for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy review_log_delete on review_log
    for delete using (user_id = auth.uid());

create policy daily_activity_select on daily_activity
    for select using (user_id = auth.uid());
create policy daily_activity_insert on daily_activity
    for insert with check (user_id = auth.uid());
create policy daily_activity_update on daily_activity
    for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy daily_activity_delete on daily_activity
    for delete using (user_id = auth.uid());

grant select, insert, update, delete on collections to authenticated;
grant select, insert, update, delete on words to authenticated;
grant select, insert, update, delete on review_log to authenticated;
grant select, insert, update, delete on daily_activity to authenticated;
