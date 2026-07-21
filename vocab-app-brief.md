# Vocabulary Learning App — Claude Code Brief

## Overview

A personal, single-user (per-account) vocabulary learning system for iOS. The user saves words in a target language, gets an auto-suggested translation, pronunciation, and example sentence (all editable), organizes them into collections, and reviews them in a swipe-based flashcard practice mode backed by lightweight spaced repetition. Progress is tracked with a daily streak and local notification reminders. Data lives in Supabase behind the simplest viable account system.

This brief reuses the proven online-sync pattern from the prior Read Later app (mock-first store → remote-replace → offline outbox), **but changes the auth/security model** because that app ran single-user with no accounts. See **Auth & Security** below — this is a hard requirement, not a preference.

---

## System Components

### 1. iOS App (SwiftUI, native)
The only client in v1. Words are added manually inside the app. (A share-sheet extension to capture a selected word/phrase from another app is a natural follow-up but is **out of scope for v1** to keep the surface small.)

### 2. Supabase Backend
Postgres + Auth + Realtime. Full-text search on words for lookup. Row Level Security **enabled**, policies scoped to `auth.uid()`.

### 3. Auth & Security
- **Auth: email OTP (passwordless) via Supabase Auth.** The user enters their email, receives a one-time code / magic link, and is signed in — no password stored or managed. Chosen for a TestFlight-only personal build: least setup, no Apple Developer portal config. Single sign-in method, so App Store guideline 4.8 (which would require Sign in with Apple *if* third-party logins were offered) does not apply.
- **SMTP note:** Supabase's default email sender is rate-limited and can be slow or land in spam. Fine at personal scale. If code delivery becomes unreliable, plug a custom SMTP provider (e.g. Resend, Postmark) into Supabase Auth settings — a config change, not a code change.
- **Row Level Security ENABLED.** Every table below has a `user_id uuid` column defaulting to `auth.uid()`. Policies use the expression `user_id = auth.uid()` — but note the clause differs by command: `USING` for SELECT/UPDATE/DELETE, `WITH CHECK` for INSERT (and *both* for UPDATE). A policy written with `USING` only leaves INSERT unconstrained, letting a client insert rows under an arbitrary `user_id`. Every table needs an explicit `WITH CHECK (user_id = auth.uid())` on insert.
- **Ship the Supabase ANON key in the app, never the service key.** The service-key-in-client pattern from the Read Later app is a security hole the moment multiple accounts exist; do not reuse it here.

---

## Database Schema

### `collections`
| Column | Type | Notes |
|---|---|---|
| id | uuid | Primary key |
| user_id | uuid | FK → auth.users, default `auth.uid()` |
| name | text | e.g. "Spanish — Travel" |
| target_language | text | BCP-47 code, e.g. `es` |
| native_language | text | BCP-47 code, e.g. `en` |
| created_at | timestamptz | |

### `words`
| Column | Type | Notes |
|---|---|---|
| id | uuid | Primary key |
| user_id | uuid | FK → auth.users, default `auth.uid()` |
| collection_id | uuid | FK → collections |
| term | text | The word/phrase in the target language |
| translation | text | Editable; auto-suggested on create |
| pronunciation | text | Optional IPA or phonetic hint; editable |
| example_sentence | text | Editable; optional auto-fetch |
| status | text | `new` / `learning` / `learnt` / `retired` — single source of truth (see Practice Mode); `CHECK (status IN ('new','learning','learnt','retired'))` |
| importance | int | 1–3; weights active-deck ordering (`ORDER BY importance DESC`) |
| know_count | int | Consecutive-ish "know" swipes on the active deck; hits `LEARNT_THRESHOLD` → graduates |
| interval_step | int | Resurface ladder index for `learnt` words: 0→7d, 1→21d, 2→60d, then `retired` |
| due_at | timestamptz | Only meaningful once `learnt`: next resurface check-in. Null/ignored while on the active deck |
| times_seen | int | Total review iterations (running count, all phases) |
| created_at | timestamptz | |
| updated_at | timestamptz | |


### `review_log` (append-only)
Satisfies "each word keeps the log of how many iterations it went through." One row per swipe.
| Column | Type | Notes |
|---|---|---|
| id | uuid | Primary key |
| user_id | uuid | default `auth.uid()` |
| word_id | uuid | FK → words |
| result | text | `know` / `dont_know` / `skip` |
| phase | text | `active` or `resurface` — which phase the word was in when swiped |
| status_before | text | |
| status_after | text | |
| reviewed_at | timestamptz | |

### `daily_activity`
Drives the streak. One row per user per calendar day (in the user's local timezone) on which any review happened.
| Column | Type | Notes |
|---|---|---|
| user_id | uuid | |
| activity_date | date | |
| reviews_count | int | |
| PRIMARY KEY | (user_id, activity_date) | |

### Delete behavior & indexing
- **Hard delete with cascade.** `words.collection_id` → `collections(id) ON DELETE CASCADE`; `review_log.word_id` → `words(id) ON DELETE CASCADE`. Deleting a collection removes its words and their review-log rows. No soft-delete (`deleted_at`) in v1 — this is a personal app with no undo requirement in scope, and soft-delete would add filtering to every query for no asked-for benefit.
- **`daily_activity` is NOT cascaded.** It's a per-day aggregate keyed to the user, not to any word, so deleting words leaves streak history intact (correct — your streak shouldn't drop because you deleted a word).
- **Search index:** do NOT use default English `tsvector` full-text search — `term` holds arbitrary target languages (German, Spanish, etc.) and English stemming/tokenization mis-handles them. Use a **`pg_trgm` GIN index** on `term` + `translation` and query by trigram similarity / `ILIKE`. It's language-agnostic, gives prefix/partial matches (what a word-lookup box actually wants), and needs no per-language config.
- **`status` CHECK constraint.** Every scheduling transition (Phase 1/2 swipe logic, active-deck query, resurface query) matches on the exact strings `new`/`learning`/`learnt`/`retired`. A stray typo from the client (e.g. an enum serializing `"learned"`) would silently fall out of every query with no error. Enforce the constraint at the DB level, not just in the Swift enum.

---

## Practice Mode (the core mechanic)

### UX (keep exactly as specified)
- User picks a collection (or "All") and a **batch size** (e.g. 10 / 20 / 30).
- Cards presented one at a time. Front shows `term`; tap to flip and reveal `translation` / `example_sentence` / pronunciation playback.
- **Swipe right = know**, **swipe left = don't know**, **swipe down = skip**.
- **Gesture-conflict note:** the real iOS collision risk is *horizontal* card swipes vs. the interactive edge-back gesture (`interactivePopGesture`) when a swipe starts near the left screen edge — not the downward swipe. Keep the card's active drag region inset from screen edges, and consider disabling the back-swipe while a review session is presented. (Downward-swipe-vs-Notification-Center is a non-issue in practice — those pull from the top status-bar edge, not the card's center hit area.)
- Session ends when the batch is exhausted; show a small summary (known / didn't-know / skipped, streak status).

### Scheduling — two-phase model (acquisition + retention)

Every word lives in one of two phases. The same three swipes mean **different things depending on phase** — this is the single most important detail to implement correctly.

**Constants (tune later):** `LEARNT_THRESHOLD = 3`, resurface ladder `= [7d, 21d, 60d]`.

#### Phase 1 — Active deck (conveyor) — for `new` / `learning` words
No dates. A stable, deterministic set the user grinds until words graduate. On swipe:
- **know (right):** `know_count += 1`. If `know_count >= LEARNT_THRESHOLD` → graduate: `status = learnt`, `interval_step = 0`, `due_at = now + 7d`. Otherwise the word stays on the deck.
- **don't know (left):** `know_count = 0`; word stays on the deck (recirculates). If it was `new`, set `status = learning`.
- **skip (down):** no change; word recirculates.

**Active-deck batch query:** words in the chosen collection where `status IN ('new','learning')`, ordered by `importance DESC, know_count ASC, created_at ASC`, limited to batch size. Deterministic order = the same ~N words keep coming up until mastered; `know_count ASC` drifts words you're doing well on toward the back so they don't dominate.

#### Phase 2 — Resurface check-ins (expanding intervals) — for `learnt` words
A learnt word is **not** gone. It re-appears when `due_at` arrives, mixed into the session. On swipe:
- **know (right):** advance the ladder. `interval_step += 1`. If `interval_step > 2` → `status = retired` (proven durable; leaves rotation). Otherwise `due_at = now + ladder[interval_step]` (21d, then 60d).
- **don't know (left):** the word did **not** survive the gap → demote. `status = learning`, `know_count = 0`, `interval_step = 0`, `due_at = null`. It rejoins the active deck.
- **skip (down):** no change; re-eligible next session.

#### Every swipe, both phases
`times_seen += 1`; append a `review_log` row (record `phase`, `status_before`, `status_after`); `updated_at = now`; write a `daily_activity` row for today (local tz).

#### How a session is assembled
1. Take due resurface words: `status = 'learnt' AND due_at <= now`, ordered `due_at ASC`.
2. Fill the rest of the batch from the active deck (query above).
3. Cap the total at batch size. If nothing is due and the deck is empty, the collection is fully retired — show a "nothing to review" state, not an empty deck.

Suggested split so retention checks never crowd out new learning: allow resurface words up to ~⅓ of the batch, remainder from the active deck (tune later).

**Accepted v1 behavior — resurface backlog:** if the user skips practice for a stretch, overdue `learnt` words accumulate and drain FIFO by `due_at` behind the ~⅓ cap; nothing ages or re-prioritizes them. This is deliberate, not an oversight — the backlog self-drains over a few sessions. Future lever (not v1): cap the visible backlog and re-space the overflow forward so a long absence doesn't create one giant catch-up pile.

#### Manual overrides
A word's `status` is user-editable in Word Detail: force `learnt`/`retired`, or reset to `learning` to throw it back on the deck. Manual edits set `due_at`/`interval_step`/`know_count` to sensible defaults for the chosen status.

> **Why two phases:** the conveyor builds recall fast but that success is partly short-term memory; retiring a word the instant it's "known" removes it exactly when retention is weakest-but-looks-strongest. The expanding resurface ladder (7 → 21 → 60 days) forces the word to survive real gaps before it's truly retired, and catches ones that decayed by dropping them back to the deck.

---

## Word Capture, Translation, Pronunciation

### Adding a word
Manual add sheet: enter `term`, choose collection, set `importance`. On entry, the app auto-suggests `translation` and (optionally) `example_sentence`; both land in editable fields the user can accept or overwrite before saving. `status` defaults to `new`, `know_count` to 0, `interval_step` to 0, `due_at` to null.

### Translation
- **Primary: Apple Translation framework** (on-device, free, no API key, works offline once the language pair is downloaded). Requires iOS 17.4+/18 depending on API surface — verify at build time.
- **Integration constraint:** it is *not* a fire-and-forget function. Translation runs through a view-attached `TranslationSession` (`.translationTask`), and the **first use of each language pair triggers a system prompt to download the offline language pack**. Practical consequence: the add-word screen owns a translation session, and the user sees a brief one-time system UI per new language pair. Design the add-word flow so a pending/first-run translation doesn't block typing or saving.
- Translation is a *suggestion*, always editable. Never block saving on a failed or not-yet-ready translation.

### Example sentence
- Hardest field to auto-fill well. Default to **user-entered**, with an optional **"Fetch example" button** as a best-effort convenience. **Tatoeba has no stable, documented official public API** — only a community-run endpoint (flaky, rate-limited) and downloadable sentence-pair data dumps. Treat the button as "might work," never a dependency; if example-fetching ever needs to be reliable, the honest path is importing Tatoeba's downloadable dumps into your own table, not calling their endpoint live. Quality/coverage also varies sharply by language.
- (An LLM call would give smoother sentences but adds a key, cost, and network dependency — out of scope for a "simple" v1.)

### Pronunciation
- **Primary: `AVSpeechSynthesizer`** — on-device TTS, free, offline, no stored audio. A speaker button on the card and detail view speaks `term` in `target_language`.
- Optional editable `pronunciation` text field for IPA / manual phonetics.
- Stored "professional" recorded audio (as Remember offers) is **out of scope v1** — it means an audio pipeline and Storage bucket for little early payoff.

---

## Screens

### Collections (home)
- List of collections with name, target→native language, word count, and learnt/total progress.
- Create / rename / delete a collection.
- Tapping a collection opens its Word List.

### Word List
- Words in the collection: `term`, `translation`, status badge, importance indicator.
- Filter: All / New / Learning / Learnt.
- Search (trigram similarity via `pg_trgm`, hits Supabase — language-agnostic, matches partial/prefix).
- Swipe actions: toggle learnt, edit, delete.
- "+" to add a word.

### Word Detail / Edit
- All fields editable: term, translation, pronunciation, example sentence, importance, status, collection.
- Speaker button (TTS). "Fetch example" button (Tatoeba).
- Shows review history summary (`times_seen`, current box, last reviewed).

### Practice
- Pick collection(s) + batch size → swipe session as specified above → summary screen.

### Stats / Streak
- Current streak, longest streak, calendar heatmap of `daily_activity`.
- Counts: total words, learnt, learning, new.

---

## Streak Logic

- A day "counts" toward the streak if the user completes **at least one review** (any swipe) that day, recorded in `daily_activity` using the **user's local timezone**.
- Current streak = consecutive days up to and including today (or yesterday, if today has no activity yet) with a `daily_activity` row.
- Compute streak client-side from `daily_activity` on launch; optionally mirror with a Postgres function later. Do not let a missed-by-timezone edge case silently break streaks — anchor all date math to the device's current timezone.

---

## Notifications

- **Local notifications** via `UNUserNotificationCenter` (no server push needed in v1 → simpler, no APNs setup).
- User sets a daily reminder time in Settings; app schedules a repeating local notification ("Time to review — keep your N-day streak").
- Request notification permission contextually (after first successful session), not on cold launch.
- **Out of scope v1:** server-driven push, smart/adaptive reminder timing.

---

## iOS Architecture

- SwiftUI + Swift Concurrency (async/await), Swift 6 strict concurrency, iOS 17+ deployment target (raise if the Translation API needs 18).
- `project.yml` as source of truth → generated `.xcodeproj` via XcodeGen (mirrors the Read Later app's tooling).
- Data layer follows the Read Later pattern: `@MainActor ObservableObject` stores (`CollectionStore`, `WordStore`, `ReviewStore`) seeded from mock data first, then swapped to a Supabase-backed implementation (fetch on launch + Realtime subscription). Build the full UI against mock data before wiring the backend.
- Offline: local SQLite cache (GRDB) for reading + a pending-writes outbox so reviews taken offline sync on reconnect. Reviews are the write path most likely to happen offline (on a train, etc.), so the outbox matters here more than it did for read-later.
- Supabase Swift SDK for the data layer once the backend exists.

---

## Tech Stack Summary

| Layer | Technology |
|---|---|
| iOS app | Swift, SwiftUI, Swift Concurrency |
| Backend | Supabase (Postgres + Auth + Realtime) |
| Auth | Email OTP (passwordless) via Supabase Auth, RLS enabled |
| Translation | Apple Translation framework (on-device) |
| Example sentences | Tatoeba API (optional fetch), else manual |
| Pronunciation | AVSpeechSynthesizer (on-device TTS) |
| Notifications | UNUserNotificationCenter (local) |
| Offline cache | GRDB (SQLite) + pending-writes outbox |
| Sync | Supabase Realtime |
| Project tooling | XcodeGen |

---

## Out of Scope (v1)

- Multi-language UI localization
- Share-sheet / browser capture extensions
- Stored "professional" pronunciation audio
- LLM-generated example sentences
- Server push notifications / adaptive reminder timing
- Pre-made / thematic word sets, AI word-set generation (à la Remember)
- Grammar lessons, conversation practice
- Web app
- Sharing collections between users

---

## Success Criteria

- Adding a word (with suggested translation) takes under 5 seconds and the word is immediately reviewable.
- A practice session of 20 cards feels fast and lag-free; swipes register instantly and sync in the background.
- Reviews taken offline persist and sync correctly on reconnect (no lost or double-counted swipes).
- The streak never breaks due to a timezone bug.
- Active-deck words recur in a stable, deterministic order (not random) until they graduate; graduating a word backfills the next one into rotation.
- Learnt words are never permanently gone until retired — they resurface on the 7/21/60-day ladder, and a failed check-in demotes them back to the active deck.
- A user's data is invisible to every other account (RLS verified).

---

## Open Decisions to Confirm

1. **Review algorithm:** SETTLED — two-phase (conveyor active deck + 7/21/60-day resurface ladder). See Practice Mode.
2. **Auth method:** SETTLED — email OTP via Supabase Auth.
3. **Tuning constants (safe to defer):** `LEARNT_THRESHOLD` (default 3), resurface ladder (default 7/21/60 days), resurface share of each batch (default ~⅓).
