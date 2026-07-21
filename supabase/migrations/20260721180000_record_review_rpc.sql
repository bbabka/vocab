-- Atomic idempotent write path for one swipe, used by the GRDB outbox drain
-- (Phase 4). Updates `words`, inserts `review_log`, and upserts
-- `daily_activity` in one transaction (Postgres functions are transactional),
-- and is safe to retry blindly: if `p_id` already exists in `review_log`,
-- this no-ops rather than double-applying.
--
-- `security invoker`, not definer: RLS must still evaluate against the
-- calling user, exactly as if the client had issued the three writes
-- directly, so `auth.uid()` inside stays scoped to whoever's JWT is on the
-- request and a caller can never touch another account's rows.
create function record_review(
    p_id uuid,
    p_word_id uuid,
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

    update words
    set status = p_status_after,
        know_count = p_know_count_after,
        interval_step = p_interval_step_after,
        due_at = p_due_at_after,
        times_seen = p_times_seen_after
    where id = p_word_id;

    -- RLS's `USING (user_id = auth.uid())` silently drops the UPDATE above
    -- to zero affected rows for a `p_word_id` the caller doesn't own, and the
    -- same zero-row result happens if the word was deleted (e.g. the client
    -- deleted it locally after queuing this review but before the outbox
    -- drained). Unlike the genuine idempotency no-op above, this is NOT
    -- safe to treat as silent success: raise a distinguishable error
    -- (SQLSTATE 'VC001') instead, so the client can tell "already synced,
    -- nothing to do" apart from "this word is gone, drop the queued review"
    -- rather than discarding the review from its outbox while believing it
    -- synced.
    get diagnostics v_updated_rows = row_count;
    if v_updated_rows = 0 then
        raise exception 'record_review: word % not found or not owned by caller', p_word_id
            using errcode = 'VC001';
    end if;

    insert into review_log (id, word_id, result, phase, status_before, status_after, reviewed_at)
    values (p_id, p_word_id, p_result, p_phase, p_status_before, p_status_after, p_reviewed_at);

    insert into daily_activity (user_id, activity_date, reviews_count)
    values (auth.uid(), p_activity_date, 1)
    on conflict (user_id, activity_date)
        do update set reviews_count = daily_activity.reviews_count + 1;
end;
$$;

-- Same explicit-grant stance as the tables: PostgREST can't reach a function
-- without an EXECUTE grant to the calling role, and there's no grant to
-- `anon` — unauthenticated calls must fail outright.
grant execute on function record_review(
    uuid, uuid, text, text, text, text, int, int, timestamptz, int, timestamptz, date
) to authenticated;
