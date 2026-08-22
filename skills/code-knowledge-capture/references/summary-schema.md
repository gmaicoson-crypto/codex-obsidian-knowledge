# Summary schema

Each feature directory contains six notes. Keep the frontmatter consistent so notes can be searched and merged across projects.

```yaml
---
type: code-feature-summary
project: <project-id>
feature: <feature-id>
status: analysis | design | implemented | verified | blocked
review: pending | accepted
source: codex
source_thread_id: <thread-id-or-unknown>
updated: YYYY-MM-DD
tags:
  - code
---
```

## `00-功能总览.md`

Stable entry point: goal, current behavior, status, key entry points, evidence links, and open risks.

## `01-实现细节.md`

Problem context, old behavior, call chain, data structures, changed files, edge cases, and compatibility notes. Record facts and cite paths or symbols when available.

## `02-实施效果.md`

Before/after behavior, test and build results, artifact identifiers, screenshots or logs, and unverified boundaries. Never convert “build succeeded” into “user scenario verified.”

## `03-知识应用总结.md`

Generalizable patterns, debugging lessons, reusable design decisions, failure modes, and where the lesson applies to another project.

## `04-后续迭代方向.md`

P0/P1/P2 improvements with acceptance criteria, dependencies, risk, and whether the item is a follow-up idea or an already-started task.

## `99-相关对话与文件.md`

Source thread IDs, repository paths, reports, artifacts, commits, and related Obsidian notes. Redact credentials and personal data.

## Project overview rule

`00-项目总览.md` is a compact index, not a duplicate of every feature note. It should list the project purpose, architecture, feature status matrix, current risks, and links to feature directories.
