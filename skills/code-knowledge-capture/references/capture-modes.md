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

## `expanded`

Use for substantial implementation, debugging, cross-module behavior, or when
the user asks for the complete learning set. Use the canonical project notes
and all six feature notes, but do not invent content to fill empty sections.
Set `detail_level: expanded` and `capture_mode: expanded`.

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

## Mode changes

Moving from compact to expanded is an additive update and requires a preview.
Moving from expanded to compact never deletes existing notes. A mode change
must not rewrite unrelated content or replace stable IDs.
