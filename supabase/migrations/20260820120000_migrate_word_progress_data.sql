-- Backfill existing per-word progress into `word_progress` rows, then drop
-- the now-migrated columns from `words`. `on conflict do nothing` guards
-- against the `words_seed_recognize_progress` trigger (added in
-- 20260820100000) having already created a recognize row for any word
-- inserted between that migration and this one.

insert into word_progress (user_id, word_id, direction, status, know_count, interval_step, due_at, times_seen, updated_at)
select user_id, id, 'recognize', status, know_count, interval_step, due_at, times_seen, updated_at
from words
on conflict (word_id, direction) do nothing;

-- Words already durable in recognize practice unlock recall retroactively.
-- Backfilled to the word's own `updated_at`, not `now()` — backfilling to
-- `now()` would fake a same-day cluster of unlocks for words that actually
-- graduated long ago, distorting stats/history.
update words
set recall_unlocked_at = updated_at
where status in ('learnt', 'retired') and recall_unlocked_at is null;

insert into word_progress (user_id, word_id, direction, status)
select user_id, id, 'recall', 'new'
from words
where status in ('learnt', 'retired')
on conflict (word_id, direction) do nothing;

alter table words
    drop column status,
    drop column know_count,
    drop column interval_step,
    drop column due_at,
    drop column times_seen;
