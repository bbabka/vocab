-- Recall Layer v2: per-direction scheduling. Progress moves off `words`
-- into `word_progress`, one row per (word, direction). See
-- vocab-rev_direction-brief.md's "Recall Layer" section.

create table word_progress (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    word_id uuid not null references words (id) on delete cascade,
    direction text not null check (direction in ('recognize', 'recall')),
    status text not null default 'new'
        check (status in ('new', 'learning', 'learnt', 'retired')),
    know_count int not null default 0,
    interval_step int not null default 0,
    due_at timestamptz,
    times_seen int not null default 0,
    updated_at timestamptz not null default now(),
    unique (word_id, direction)
);

create trigger word_progress_set_updated_at
    before update on word_progress
    for each row
    execute function set_updated_at();

-- Structural guarantee, not a client convention: every word gets its
-- `recognize` progress row created here, not by whichever client code path
-- happens to insert into `words`. Matches the brief's "lazy creation"
-- principle without depending on every future insert path remembering to
-- also write the progress row.
create function seed_recognize_progress() returns trigger
    language plpgsql as $$
begin
    insert into word_progress (user_id, word_id, direction, status)
    values (new.user_id, new.id, 'recognize', 'new');
    return new;
end;
$$;

create trigger words_seed_recognize_progress
    after insert on words
    for each row
    execute function seed_recognize_progress();

-- The one-way unlock latch. `recall` unlocks the first time `recognize`
-- reaches `learnt`, permanently (see brief: "Gated unlock"). This lives as
-- a DB trigger, not app/RPC logic, so it fires identically regardless of
-- which write path moved `recognize` to `learnt` — including a manual
-- status override from Word Detail, which does not go through
-- `record_review`. A gated write here (an `if direction == recognize`
-- check duplicated in every write path) is exactly the shape of bug this
-- structural approach avoids.
create function unlock_recall_progress() returns trigger
    language plpgsql as $$
begin
    update words
    set recall_unlocked_at = now()
    where id = new.word_id and recall_unlocked_at is null;

    insert into word_progress (user_id, word_id, direction, status)
    values (new.user_id, new.word_id, 'recall', 'new')
    on conflict (word_id, direction) do nothing;

    return new;
end;
$$;

create trigger word_progress_unlock_recall
    after update on word_progress
    for each row
    when (new.direction = 'recognize' and new.status = 'learnt' and old.status is distinct from 'learnt')
    execute function unlock_recall_progress();

alter table words add column recall_unlocked_at timestamptz;

-- RLS: same shape as every other user-owned table (see
-- 20260721150100_rls_policies.sql) — `USING` for select/delete, both
-- `USING` and `WITH CHECK` for update, `WITH CHECK` only for insert. The
-- `WITH CHECK`-on-insert clause is not optional: without it a client could
-- insert a word_progress row under an arbitrary user_id.
alter table word_progress enable row level security;

create policy word_progress_select on word_progress
    for select using (user_id = auth.uid());
create policy word_progress_insert on word_progress
    for insert with check (user_id = auth.uid());
create policy word_progress_update on word_progress
    for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy word_progress_delete on word_progress
    for delete using (user_id = auth.uid());

grant select, insert, update, delete on word_progress to authenticated;
