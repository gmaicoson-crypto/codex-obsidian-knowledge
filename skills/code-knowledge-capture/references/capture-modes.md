# Capture modes

Choose one mode before drafting and expose it in the preview. Preserve the
user's explicit choice. If the user does not choose, use `expanded`; for a
small isolated change, you may recommend `compact` but must not silently omit
documents.

## `compact`

Use for a small, isolated implementation or explanation that does not change
project architecture. Create or update:

- project `00-项目总览.md` only when its stable feature index changes;
- feature `00-功能总览.md`;
- feature `01-实现细节.md`;
- feature `99-相关对话与文件.md`.

Fold the verification boundary and one reusable lesson into the feature
overview. Omit empty roadmap and architecture documents. Set
`detail_level: compact` and `capture_mode: compact`.

Compact changes the document set, not the truth standard. The retained feature
overview still needs one mechanism explanation, one relevant failure or
boundary, and one evidence limitation. It may omit the full deep audit only
when the user explicitly chooses compact mode; do not silently make an
expanded capture shallow.

Compact also does not mean “test summary.” Keep the feature overview focused on
the useful mechanism and reusable lesson. Fold verification into one short
claim-level boundary statement and omit raw commands, logs, build output, and
unrelated implementation process.

## `expanded`

Use for substantial implementation, debugging, cross-module behavior, or when
the user asks for the complete learning set. Use the canonical project notes
and all six feature notes, but do not invent content to fill empty sections.
Set `detail_level: expanded` and `capture_mode: expanded`.

Expanded mode also requires the depth audit in
[deep-exploration-guide.md](deep-exploration-guide.md). The audit covers
mechanism, evidence, counterfactual/failure, boundary, and transfer condition;
it is not satisfied by adding more prose or repeating the call chain.

Expanded means deeper knowledge explanation, not more test or engineering
reporting. The implementation note should normally use production code and
behavior-defining boundaries. Include test code, detailed test cases, or build
evidence only when they teach the contract, failure mode, or verification idea
behind the knowledge being captured.

For the first capture of a project, or whenever the existing project baseline is
missing or stale, expanded mode includes a project-baseline pass before the
feature pass. The preview separates project-note updates from feature-note
updates. Later feature captures may reuse a confirmed baseline and refresh it only
when repository-wide evidence shows a stable architecture, boundary, or shared
term has changed.

## `architecture-only`

Use when the request is to understand system boundaries, components, terms,
or end-to-end architecture rather than one feature implementation. Create or
update only:

- project `00-项目总览.md`;
- project `01-架构与术语.md`.

Do not create a feature directory unless the user separately requests one.
Set `detail_level: expanded` and `capture_mode: architecture-only`.

## `update-only`

Use only when the user explicitly asks to patch existing knowledge without
creating new notes. Search and read the existing project/feature notes first.
If the target notes do not exist, report the blocker in the preview instead of
falling back to creation. Preserve unrelated sections and accepted facts. Set
`capture_mode: update-only`; retain the existing `detail_level` unless the user
asks to change it.

This exception also applies to the project baseline: an explicit `update-only`
request may not create missing project overview or architecture notes. Report the
missing mainline target in the preview instead.

## Mode changes

Moving from compact to expanded is an additive update and requires a preview.
Moving from expanded to compact never deletes existing notes. A mode change
must not rewrite unrelated content or replace stable IDs.
