-- Vocab core schema: collections, words, review_log, daily_activity.
-- See vocab-app-brief.md's "Database Schema" and "Practice Mode" sections
-- for the field-by-field rationale; this migration is the literal DDL for
-- that spec.

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

create table collections (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    name text not null,
    target_language text not null,
    native_language text not null,
    created_at timestamptz not null default now()
);

create table words (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    collection_id uuid not null references collections (id) on delete cascade,
    term text not null,
    translation text not null default '',
    pronunciation text,
    example_sentence text,
    status text not null default 'new'
        check (status in ('new', 'learning', 'learnt', 'retired')),
    importance int not null default 2,
    know_count int not null default 0,
    interval_step int not null default 0,
    due_at timestamptz,
    times_seen int not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Single trigram index over both searchable columns: language-agnostic
-- (unlike English tsvector stemming, which mishandles arbitrary target
-- languages), and gives the partial/prefix matches a word-lookup box needs.
create index words_search_trgm_idx
    on words using gin ((term || ' ' || translation) gin_trgm_ops);

-- Belt-and-suspenders: `updated_at` is later load-bearing for last-write-wins
-- reconciliation between GRDB and Realtime (Phase 4/5), so maintain it with
-- a trigger rather than trusting every client write path to set it.
create function set_updated_at() returns trigger
    language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger words_set_updated_at
    before update on words
    for each row
    execute function set_updated_at();

create table review_log (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    word_id uuid not null references words (id) on delete cascade,
    result text not null check (result in ('know', 'dont_know', 'skip')),
    phase text not null check (phase in ('active', 'resurface')),
    status_before text not null
        check (status_before in ('new', 'learning', 'learnt', 'retired')),
    status_after text not null
        check (status_after in ('new', 'learning', 'learnt', 'retired')),
    reviewed_at timestamptz not null default now()
);

-- Deliberately no FK to `words`: deleting a word must not erase the user's
-- streak history. One row per user per local calendar day.
create table daily_activity (
    user_id uuid not null references auth.users (id) on delete cascade,
    activity_date date not null,
    reviews_count int not null default 0,
    primary key (user_id, activity_date)
);
