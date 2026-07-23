-- A term frequently has more than one sense (e.g. Spanish "banco" = "bank"
-- or "bench") — replace the single `translation` column with a `meanings`
-- jsonb array, each entry carrying its own part-of-speech marker. Stored as
-- jsonb rather than a child table: meanings are a small, ordered, word-owned
-- list with no need for independent querying or joins across them, matching
-- the rest of this schema's preference for simplicity over normalization
-- where nothing actually depends on the extra structure.

alter table words add column meanings jsonb not null default '[]'::jsonb;

update words
set meanings = case
    when translation = '' then '[]'::jsonb
    else jsonb_build_array(
        jsonb_build_object('id', gen_random_uuid(), 'translation', translation, 'part_of_speech', 'other')
    )
end;

-- The old index expression references `translation` directly, so it must be
-- dropped before the column itself can go.
drop index words_search_trgm_idx;
alter table words drop column translation;

-- Postgres CHECK constraints can't contain a subquery directly, so the
-- per-element validation has to live in a function instead — mirrors the
-- `WordStatus`/`ReviewResult`/etc. CHECK constraints elsewhere in this
-- schema: `part_of_speech` values are validated against the exact same set
-- `PartOfSpeech.allCases` provides client-side (see
-- `PartOfSpeechRawValueTests`, the canary test guarding against drift).
create function words_meanings_part_of_speech_valid(meanings jsonb) returns boolean
    language sql immutable as $$
    select not exists (
        select 1 from jsonb_array_elements(meanings) as m
        where m ->> 'part_of_speech' not in (
            'noun', 'verb', 'adjective', 'adverb', 'pronoun',
            'preposition', 'conjunction', 'interjection', 'other'
        )
    )
$$;

alter table words add constraint words_meanings_part_of_speech_check
    check (words_meanings_part_of_speech_valid(meanings));

-- Flattens `meanings` into space-joined translation text so the trigram
-- index can still substring-match across every sense of a word, not just
-- the raw jsonb text representation (which would also match on stray `id`s,
-- punctuation, and `part_of_speech` values).
create function word_meanings_text(meanings jsonb) returns text
    language sql immutable as $$
    select coalesce(string_agg(m ->> 'translation', ' '), '')
    from jsonb_array_elements(meanings) as m
$$;

create index words_search_trgm_idx
    on words using gin ((term || ' ' || word_meanings_text(meanings)) gin_trgm_ops);
