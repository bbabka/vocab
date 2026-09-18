# Vocabulary Learning App — Current Implementation

This document describes the system as it actually exists in the repo today, as a companion to `vocab-app-brief.md`. It follows the same section order as the brief. Where the implementation matches the brief exactly, that's noted briefly; where it diverges, the actual behavior is described along with the reason (where one is documented in code/comments).

---

## System Components

- **iOS app**: SwiftUI, native, single client. Manual add-word flow only (no share-sheet extension), as specified.
- **Supabase backend**: Postgres + Auth + Realtime, `pg_trgm` extension enabled. Six migrations under `supabase/migrations/`.
- **Auth & Security**: implemented as specified — email OTP (code entry, not magic link) via Supabase Auth, RLS enabled on every table, only the anon/publishable key shipped in the client.

---

## Auth & Security

- `AuthStore` (`ios/Vocab/Stores/AuthStore.swift`) drives `signInWithOTP` → `verifyOTP`; `AuthView` is the entry sheet.
- Every table has `user_id uuid not null default auth.uid() references auth.users(id) on delete cascade`.
- RLS policies (`supabase/migrations/20260721150100_rls_policies.sql`) correctly split `USING` (SELECT/UPDATE/DELETE) from `WITH CHECK` (INSERT, and both for UPDATE) on every table — matching the brief's specific warning about INSERT-unconstrained policies.
- `grant ... to authenticated` only; no grants to `anon`.
- `ios/Vocab/Resources/SupabaseConfig.swift` ships only the publishable/anon key. No service key appears anywhere in client code.

---

## Database Schema (as it actually stands today)

### `collections`
Matches the brief exactly: `id`, `user_id` (default `auth.uid()`), `name`, `target_language`, `native_language`, `created_at`.

### `words`
Same as the brief **except the `translation` column no longer exists.**

| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| user_id | uuid | default `auth.uid()` |
| collection_id | uuid | FK → collections, `ON DELETE CASCADE` |
| term | text | |
| **meanings** | **jsonb** | **Replaces `translation`.** Array of `{id, translation, part_of_speech}`. Added in `20260722100000_word_meanings.sql`. |
| pronunciation | text | nullable, editable |
| example_sentence | text | nullable, editable |
| status | text | `new`/`learning`/`learnt`/`retired`, CHECK-constrained — matches brief |
| importance | int | default 2 |
| know_count | int | default 0 |
| interval_step | int | default 0 |
| due_at | timestamptz | nullable |
| times_seen | int | default 0 |
| created_at / updated_at | timestamptz | `updated_at` maintained by a `BEFORE UPDATE` trigger (`set_updated_at()`), not left to client writes |

**Why the change:** a term frequently has more than one sense (the migration's comment example: Spanish "banco" = "bank" or "bench"). Rather than one `translation` string, each word now carries an ordered `meanings` array, each entry tagged with a `part_of_speech` (validated via a Postgres function `words_meanings_part_of_speech_valid`, since CHECK constraints can't subquery a jsonb array directly — mirrors the client-side `PartOfSpeech.allCases` enum). Stored as jsonb rather than a child table because the list is small, ordered, and word-owned with no independent-query need.

This ripples through `Word.swift` (`meanings: [WordMeaning]`), `AddWordView`, `WordDetailView`, and `WordListView`, all of which read/write `meanings[]` rather than a single translation field. A backward-compatible initializer on `Word` still accepts a single `translation:` string for simpler call sites (tests, mock data).

### `review_log`
Matches the brief: append-only, `result` (`know`/`dont_know`/`skip`), `phase` (`active`/`resurface`), `status_before`/`status_after`, `reviewed_at`. FK to `words` with `ON DELETE CASCADE`.

### `daily_activity`
Matches the brief: `(user_id, activity_date)` primary key, `reviews_count`. No FK to `words`/`collections` (by design — deleting words must not erase streak history), only to `auth.users`.

### Delete behavior & indexing
- Cascades exactly as specified: `words.collection_id → collections`, `review_log.word_id → words`, both `ON DELETE CASCADE`. `daily_activity` is not cascaded from word/collection deletes.
- No soft-delete anywhere.
- **`pg_trgm` GIN index present and correctly maintained** across the schema change: originally `gin ((term || ' ' || translation) gin_trgm_ops)`, updated in the meanings migration to `gin ((term || ' ' || word_meanings_text(meanings)) gin_trgm_ops)`, where `word_meanings_text()` flattens the jsonb array's `translation` fields into space-joined text (so the index matches across every sense of a word without also matching stray `id`s or `part_of_speech` values).
- **This index is currently unused by the client.** Word List search (`ios/Vocab/Views/WordListView.swift`) filters the already-loaded, in-memory word list with `localizedCaseInsensitiveContains` rather than issuing an `ilike`/trigram query to Supabase. The DB-side piece is fully built; the client-side piece that would use it isn't wired up.
- `status` CHECK constraint (`new`/`learning`/`learnt`/`retired`) present on both `words.status` and `review_log.status_before`/`status_after`, exactly as specified.

---

## Practice Mode (the core mechanic)

### UX
- Collection (or "All") + batch size (10/20/30) picker — `PracticeSetupView.swift`.
- Card front shows `term`; tap flips to reveal meanings/example/pronunciation — `PracticeSessionView.swift`.
- **Swipe right = know, swipe left = don't know — implemented as specified.**
- **Skip is a tap button, not a swipe-down gesture.** The drag gesture is horizontal-only (`dragOffset` only tracks `translation.width`). The brief marked this UX section "keep exactly as specified," including swipe-down-to-skip; the implementation departs from that one gesture in favor of a dedicated button.
- **Gesture-conflict handling differs from the brief's suggested mechanism.** Rather than insetting the drag hit-region from the screen edge and/or disabling `interactivePopGesture`, the practice session is presented as a `fullScreenCover` (not pushed onto a `NavigationStack`), which sidesteps the edge-swipe-back conflict entirely since there's no pop gesture to collide with. Functionally solves the same problem, by a different route.
- Session summary screen (known/don't-know/skipped counts, streak status) — `PracticeSummaryView.swift`, as specified.

### Scheduling — two-phase model
Implemented exactly as specified, including the tuning constants:
- `LEARNT_THRESHOLD = 3`, resurface ladder `[7, 21, 60]` days — `ReviewScheduler.swift`.
- **Phase 1 (active deck):** know → `know_count += 1`, graduates to `learnt`/`interval_step = 0`/`due_at = now + 7d` at threshold; don't-know → `know_count = 0`, `new → learning`; skip → no change. All recirculate on the deck.
- Active-deck query order: `importance DESC, know_count ASC, created_at ASC`, limited to batch size — matches brief exactly.
- **Phase 2 (resurface):** know → `interval_step += 1`, advances to next ladder rung or retires past index 2; don't-know → demotes to `learning`, resets `know_count`/`interval_step`/`due_at`; skip → no change. Matches brief exactly.
- **Session assembly:** due resurface words (`status = 'learnt' AND due_at <= now`, ordered `due_at ASC`) capped at ~⅓ of batch, backfilled from the active-deck query, capped at total batch size. FIFO backlog-drain behavior for overdue resurface words is implemented and tested as the brief's "accepted v1 behavior" describes.
- "Nothing to review" state when both queries are empty — matches brief.
- Every swipe: `times_seen += 1`, `review_log` row appended, `updated_at` bumped, `daily_activity` row written for today — all persisted atomically server-side via a `record_review` Postgres RPC (`20260721180000_record_review_rpc.sql`), not as separate client round-trips.
- Manual status override in Word Detail resets `know_count`/`interval_step`/`due_at` to sensible defaults per target status, as specified.

This entire section is a close, well-tested match to the brief (see `ReviewSchedulerTests.swift`, `SessionAssemblerTests.swift`).

---

## Word Capture, Translation, Pronunciation

- **Adding a word**: term, collection, importance entered in `AddWordView`; translation auto-suggested into an editable field on entry. `status` defaults to `new`, `know_count`/`interval_step` to 0, `due_at` to null — matches brief. No pronunciation field at add-time (only set later in Word Detail) — not something the brief explicitly required at add-time, but worth noting since it's the only place `pronunciation` is currently editable.
- **Translation**: Apple Translation framework via `.translationTask`/`TranslationSession`, availability checked at runtime (not hardcoded), debounced (~400ms) so typing isn't blocked, failures leave the field untouched and never block Save — matches brief's integration-constraint guidance closely.
- **Example sentence**: Tatoeba fetch is best-effort (`TatoebaService.swift`), failures collapse to a dismissible "might not work" state, never a save-blocking dependency — matches brief.
- **Pronunciation**: `AVSpeechSynthesizer`-based speaker button on both the practice card and Word Detail (`SpeechService.swift`); editable `pronunciation` text field on Word Detail — matches brief. No stored/recorded audio — matches "out of scope."

---

## Screens

### Collections (home)
Name, target→native language, word count, learnt/total progress, create/rename/delete — matches brief.

### Word List
- Filter (All/New/Learning/Learnt) — matches brief.
- **Search is local/in-memory (`localizedCaseInsensitiveContains` over the already-loaded word list), not a Supabase `pg_trgm`/`ilike` query.** The DB index exists (see Database Schema above) but isn't called from the client. Functionally similar for a single-user dataset that's already fully loaded, but doesn't match the brief's "hits Supabase" description.
- **Swipe actions are delete-only.** The brief specifies swipe-to-toggle-learnt, swipe-to-edit, and swipe-to-delete; only `.onDelete` is implemented. Edit is reached by tapping into the row (navigation, not a swipe action); there's no swipe-to-toggle-learnt anywhere.
- "+" to add a word — matches brief.

### Word Detail / Edit
- All fields editable: term, meanings (replacing single translation), pronunciation, example sentence, importance, status, collection — matches brief (modulo the meanings schema change).
- Speaker button and "Fetch example" button present — matches brief.
- **Review history summary is partial.** Status, importance, times seen, know count, and next check-in (`due_at`) are shown. **"Last reviewed" is not surfaced anywhere on this screen**, even though `review_log` is already fetched into `ReviewStore` — the brief calls for `times_seen`, current box, and last reviewed; the first two are present, the third isn't wired up.

### Practice
Matches brief (see Practice Mode above).

### Stats / Streak
Current streak, longest streak, calendar heatmap of `daily_activity`, word counts by status — matches brief.

---

## Streak Logic

Matches the brief exactly. `daily_activity` day-counting anchored to the device's local timezone via `Calendar.current` (`CalendarDay.swift`), current streak = consecutive days through today-or-yesterday-if-today-empty (`StreakCalculator.swift`), with tests covering DST and month-boundary edge cases.

---

## Notifications

Matches the brief exactly. Local notifications via `UNUserNotificationCenter` (`NotificationScheduler.swift`), daily repeating reminder with streak count in the body, permission requested contextually after the first completed practice session (gated by `@AppStorage` flags so it's asked once) rather than at cold launch.

---

## iOS Architecture

- SwiftUI + Swift Concurrency, Swift 6 strict concurrency (`project.yml`).
- **Deployment target is iOS 18.0, not 17+.** The brief explicitly pre-authorized this ("raise if the Translation API needs 18") — `project.yml` documents that `TranslationSession.Configuration` requires 18.0. Not a deviation from intent, just noting the concrete target.
- `project.yml` is the XcodeGen source of truth, as specified.
- Mock-first → remote-replace → offline-outbox pattern implemented as specified: `@MainActor ObservableObject` stores (`CollectionStore`, `WordStore`, `ReviewStore`, `AuthStore`) seeded from `MockData`, swapped to Supabase via `loadFromRemote()` + a Realtime subscription (`RealtimeService.swift`).
- Offline: GRDB SQLite cache (`AppDatabase.swift`) plus a `pending_reviews` outbox table, drained on reconnect (`ConnectivityMonitor.swift` → `WordStore.drainOutbox()`), covering ordering, idempotency, and partial/permanent failure — matches brief, with meaningful test coverage (`OutboxDrainTests.swift`).

---

## Tech Stack Summary

| Layer | Technology | Status |
|---|---|---|
| iOS app | Swift, SwiftUI, Swift Concurrency | as specified |
| Backend | Supabase (Postgres + Auth + Realtime) | as specified |
| Auth | Email OTP via Supabase Auth, RLS enabled | as specified |
| Translation | Apple Translation framework (on-device) | as specified |
| Example sentences | Tatoeba (optional fetch), else manual | as specified |
| Pronunciation | AVSpeechSynthesizer (on-device TTS) | as specified |
| Notifications | UNUserNotificationCenter (local) | as specified |
| Offline cache | GRDB (SQLite) + pending-writes outbox | as specified |
| Sync | Supabase Realtime | as specified |
| Project tooling | XcodeGen | as specified, target raised to iOS 18 |
| Word translation storage | `words.meanings` (jsonb array) | **changed from brief's single `words.translation` column** |
| Word List search | client-side in-memory filter | **changed from brief's Supabase `pg_trgm` query** — the DB index still exists, unused |

---

## Summary of Deviations from the Brief

1. **`words.translation` → `words.meanings` (jsonb array of `{translation, part_of_speech}`)** — deliberate redesign to support multiple senses per word; documented in migration comments. Ripples through every screen that touches a word's translation.
2. **Word List search is a local in-memory filter, not a Supabase `pg_trgm` query** — the trigram GIN index is built and correctly kept in sync with the `meanings` migration, but nothing in the client calls it.
3. **Practice card "skip" is a tap button, not a swipe-down gesture** — the brief marked this UX section "keep exactly as specified"; the drag gesture is horizontal-only.
4. **Word List swipe actions are delete-only** — no swipe-to-toggle-learnt, no swipe-to-edit (edit is navigation-only).
5. **Word Detail's review history omits "last reviewed"** — times seen, know count, status, and next check-in are shown; last-reviewed timestamp isn't, despite `review_log` already being loaded into `ReviewStore`.

Everything else — RLS/auth model, cascade deletes, the two-phase scheduling engine and its constants, streak logic, notifications, Translation/Tatoeba/TTS integration, and the offline mock-first/outbox architecture — matches the brief closely.
