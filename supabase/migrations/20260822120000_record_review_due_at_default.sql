-- `p_due_at_after` had no default, so any RPC caller that omits it when
-- `nil` (as the iOS client's synthesized `Encodable` used to for an
-- Optional) gets a "could not find function" error from PostgREST instead
-- of a clean call. The client now encodes the key explicitly as `null`
-- (see `PendingReviewAPI.Params`), but that's not defense-in-depth on its
-- own — this makes the RPC itself tolerant of a caller omitting the
-- parameter entirely, since `new`/`learning` words (the common case) always
-- pass `nil` here anyway. The three params after it get `default null` too
-- only because Postgres requires every parameter following a defaulted one
-- to have a default as well — they're always supplied by every real caller,
-- this isn't inviting them to be left out.

create or replace function record_review(
    p_id uuid,
    p_word_id uuid,
    p_direction text,
    p_result text,
    p_phase text,
    p_status_before text,
    p_status_after text,
    p_know_count_after int,
    p_interval_step_after int,
    p_due_at_after timestamptz default null,
    p_times_seen_after int default null,
    p_reviewed_at timestamptz default null,
    p_activity_date date default null
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
