# Review and safety policy

## Always preview

Preview before:

- creating a new feature directory;
- updating an existing feature note;
- changing `00-项目总览.md`;
- merging two feature notes;
- changing status from `analysis` or `design` to `implemented` or `verified`.

## Safe automatic behavior

Before approval, read-only inspection and draft generation are allowed. After approval, creating a new note and updating the approved target notes are allowed. Do not delete notes, overwrite unrelated sections, or modify source repositories as part of capture.

## Evidence confidence

Use `verified` only when the evidence matches the claim. Examples:

- Static inspection only: `analysis`.
- Code changed but no test: `implemented`.
- Tests/build pass but no real-device or user-flow check: `implemented` with a clearly stated verification boundary.
- Code, relevant tests, and the claimed runtime scenario all pass: `verified`.

## Sensitive content

Do not write API keys, passwords, bearer tokens, private keys, cookies, or unredacted personal identifiers. Replace them with `[REDACTED]` and keep only the fact that a credential or identifier was used.

## Duplicate handling

Use the combination of `project`, `feature`, `source_thread_id`, and a content hash when available. If the same task is summarized again, show an update preview instead of creating a second note. If two different threads discuss the same feature, propose a merge and list both sources.
