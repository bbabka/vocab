-- `record_review` now writes to `word_progress` (keyed by word_id +
-- direction) instead of `words`, and `review_log` gains `direction` so
-- history stops being lossy the moment recall ships.
--
-- The rewrite preserves the original RPC's contract exactly (see
-- 20260721180000_record_review_rpc.sql), not just its math:
--   - idempotent no-op via `review_log.id` dedupe, so a blind outbox retry
--     never double-applies;
--   - a distinguishable 'VC001' error for "progress row not found or not
--     owned by caller" vs. silent idempotent success — the client relies on
--     telling those apart to decide whether to drop the queued review;
--   - `security invoker`, so RLS still evaluates against the calling user.

alter table review_log add column direction text not null default 'recognize'
    check (direction in ('recognize', 'recall'));

drop function if exists record_review(
    uuid, uuid, text, text, text, text, int, int, timestamptz, int, timestamptz, date
);

create function record_review(
    p_id uuid,
    p_word_id uuid,
    p_direction text,
    p_result text,
    p_phase text,
    p_status_before text,
    p_status_after text,
    p_know_count_after int,
    p_interval_step_after int,
    p_due_at_after timestamptz,
    p_times_seen_after int,
    p_reviewed_at timestamptz,
    p_activity_date date
) returns void
    language plpgsql
    security invoker
as $$
declare
    v_updated_rows int;
begin
    if exists (select 1 from review_log where id = p_id) then
        return;
    end if;

    update word_progress
    set status = p_status_after,
        know_count = p_know_count_after,
        interval_step = p_interval_step_after,
        due_at = p_due_at_after,
        times_seen = p_times_seen_after
    where word_id = p_word_id and direction = p_direction;

    -- Same trap as the original RPC: RLS's `USING (user_id = auth.uid())`
    -- silently zero-row-affects the UPDATE above for a row the caller
    -- doesn't own, or one that's gone (word deleted, or the recall row not
    -- yet unlocked). Not safe to treat as idempotent success — raise VC001
    -- so the client can distinguish it from "already synced".
    get diagnostics v_updated_rows = row_count;
    if v_updated_rows = 0 then
        raise exception 'record_review: word_progress % / % not found or not owned by caller', p_word_id, p_direction
            using errcode = 'VC001';
    end if;

    insert into review_log (id, word_id, direction, result, phase, status_before, status_after, reviewed_at)
    values (p_id, p_word_id, p_direction, p_result, p_phase, p_status_before, p_status_after, p_reviewed_at);

    insert into daily_activity (user_id, activity_date, reviews_count)
    values (auth.uid(), p_activity_date, 1)
    on conflict (user_id, activity_date)
        do update set reviews_count = daily_activity.reviews_count + 1;
end;
$$;

grant execute on function record_review(
    uuid, uuid, text, text, text, text, text, int, int, timestamptz, int, timestamptz, date
) to authenticated;
