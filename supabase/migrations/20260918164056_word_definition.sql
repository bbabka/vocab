-- Same-language explanation of `term` (e.g. an English word's English
-- definition), fetched via the client's on-device FoundationModels lookup.
-- Kept as its own column rather than folded into `meanings` (translations
-- into the collection's native language) — mirrors `example_sentence`
-- getting its own column rather than living inside them.
alter table words add column definition text;
