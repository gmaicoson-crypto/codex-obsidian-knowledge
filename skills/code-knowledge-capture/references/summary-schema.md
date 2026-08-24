# Summary schema

Each feature directory contains six notes. Keep the frontmatter consistent so notes can be searched and merged across projects.

```yaml
---
type: code-feature-summary
schema_version: 2
note_kind: feature-overview | implementation-details | implementation-effect | knowledge-application | iteration-roadmap | source-index
project: <project-id>
feature: <feature-id>
status: analysis | design | implemented | verified | blocked
review: pending | accepted
source: codex
source_thread_id: <thread-id-or-unknown>
capture_id: <stable-capture-id>
evidence_hash: <sha256>
source_commit: <git-sha-or-unknown>
verified_at: <ISO-8601-timestamp-or-null>
updated: YYYY-MM-DD
audience: beginner-programmer
detail_level: compact | expanded
capture_mode: compact | expanded | architecture-only | update-only
tags:
  - code
---
```

`schema_version: 2` identifies the query and migration contract. `note_kind`
distinguishes the six feature documents without relying on filenames.
`capture_id` is the idempotency key for one evidence set and `evidence_hash`
is the SHA-256 of its canonical evidence manifest. `source_commit` anchors
code locations to a repository state. Set `verified_at` only when the status is
`verified`; otherwise use `null`.

`audience: beginner-programmer` marks the default reader. `capture_mode` says
which document set was requested; `detail_level` describes the prose density.
Older notes without these fields remain valid. An update preview may migrate
them to schema version 2 without changing stable project or feature IDs.

## Identity and duplicate detection

Before previewing a write, build a canonical evidence manifest containing the
project ID, feature ID, source thread ID when known, source commit when known,
relevant file/symbol identifiers, decisions, and exact verification results.
Normalize line endings and sort unordered file/test entries, then compute its
SHA-256 as `evidence_hash`. Never include secret values in the manifest.

Use `capture_id` in this order:

1. `codex:<thread-id>:<project>:<feature>:<hash-prefix>` when a source thread ID
   is available;
2. `<project>:<feature>:<source-commit>:<hash-prefix>` when a commit is known;
3. `<project>:<feature>:<hash-prefix>` otherwise.

An existing matching `capture_id` or `evidence_hash` means the evidence is
already captured. Preview no write when content is unchanged; otherwise show
only the metadata or merge delta. Do not create a second feature directory.

## Capture modes

Read [capture-modes.md](capture-modes.md) for document selection and mode
boundaries. The default remains `expanded`. The preview must name the selected
mode and every note that will be created, patched, or intentionally omitted.

For `expanded` captures, also read [deep-exploration-guide.md](deep-exploration-guide.md).
It defines the depth gate used below; a populated heading or a longer note is
not evidence that the concept was understood.

## Detail standard

“详细” means evidence-dense, not merely long. The summary should explain the
problem, the reasoning, the implementation, and the limits of the evidence.
For every important conclusion, use one of these labels when the distinction
is not obvious from the section:

- `[事实]` — directly supported by a conversation decision, source file,
  command result, test, build, artifact, or note.
- `[推断]` — a reasoned interpretation that is not directly proven.
- `[计划]` — proposed follow-up work, not an implemented result.
- `[待确认]` — an unresolved question or missing evidence.

“深入探究” means that the reader can follow a causal chain and predict a
nearby case. For every material conclusion, connect:

```text
现象/输入 → 前置条件 → 中间数据或状态 → 关键机制 → 输出/信号
```

Then add the evidence for each important transition, one relevant
counterfactual or failure path, the boundary where the explanation stops, and
the conditions under which the lesson transfers. If a counterfactual was not
run, label it `未验证`; do not turn an expected result into a fact. A glossary,
file list, call-chain list, or conclusion without the mechanism and evidence
boundary is incomplete.

Use the following depth audit in the preview:

| Core question | Mechanism | Evidence | Counterfactual/failure | Boundary | Transfer condition | Audit status |
|---|---|---|---|---|---|---|

The audit status is `已展开`, `部分展开（列出缺口）`, or
`无证据（列出最小验证）`. Missing evidence does not require inventing an
answer; it requires recording the smallest safe check and what cannot yet be
claimed.

An expanded feature capture should cover all of the following, using “无证据”
or “未验证” rather than inventing detail when evidence is absent:

1. **Context and scope** — symptom, impact, trigger, goals, non-goals, and
   constraints.
2. **Behavior and structure** — before/after behavior, entry points, call
   chain, data/control flow, state transitions, invariants, and boundaries.
3. **Mechanism and causality** — why the main transitions produce the observed
   result, which conditions enable them, and what changes if a key condition is
   removed or replaced.
4. **Decision record** — chosen approach, alternatives considered, trade-offs,
   compatibility assumptions, and why the decision fits the evidence.
5. **Implementation evidence** — changed files, symbols, configuration, and
   1–3 short source excerpts with file and symbol/line metadata.
6. **Verification** — checks run, exact results when available, runtime scope,
   regression signal, artifacts, and explicit unverified boundaries.
7. **Reusable knowledge** — general rules, failure modes, debugging steps,
   anti-patterns, transfer conditions, and terms.
8. **Next actions** — prioritized follow-ups with acceptance criteria,
   dependencies, risk, and current status.

## Beginner learning standard

The notes are learning material, not only a development record. Follow
[beginner-learning-guide.md](beginner-learning-guide.md) and include:

1. **Learning goals and prerequisites** — what the reader will understand and
   the smallest set of concepts needed first.
2. **Plain language plus technical evidence** — introduce the mental model,
   then connect it to exact files, symbols, data, and tests.
3. **Project-grounded vocabulary** — define 5–12 high-value terms in the
   project architecture note; feature notes add only feature-specific terms.
4. **Guided code reading** — for each core excerpt identify input, processing,
   output/side effect, next consumer, essential syntax, and failure signal.
5. **Architecture at three zoom levels** — system boundary, component map, and
   a numbered end-to-end flow.
6. **Debugging path** — observable symptom, first evidence to inspect, how to
   narrow the cause, and how to verify a fix.
7. **Retrieval practice** — 3–5 explain-back questions and 1–3 safe exercises
   with expected observations or answer points.

Do not teach unrelated language or framework fundamentals. Link concepts to
this repository and disclose the evidence boundary.

Minimum completeness checks for an expanded feature summary:

- `00-功能总览.md` contains a concise conclusion, scope/non-goals, status,
  learning goals/prerequisites, a plain-language mental model, evidence map,
  a causal mechanism, 3–7 why/how-if questions (or an explicit evidence
  limitation for a smaller item), and open questions.
- `01-实现细节.md` contains at least one end-to-end flow and one decision or
  trade-off; every material change is tied to a file and symbol when known;
  code examples explain input, processing, output, syntax, failure signal, and
  why the highlighted step changes behavior. It also contains one normal path,
  one error/boundary path, and one counterfactual or alternative.
- `02-实施效果.md` separates test/build evidence from runtime or user-flow
  verification, maps each evidence item to what it does and does not prove,
  and records at least one boundary or “未验证” statement.
- `03-知识应用总结.md` contains at least two reusable rules or lessons and
  says when each one does and does not apply, explains the mechanism and a
  counterexample/failure signal for each, and contains self-check questions
  and safe exercises with expected observations.
- `04-后续迭代方向.md` records acceptance criteria for each non-empty item.
- `99-相关对话与文件.md` acts as an evidence ledger rather than a bare list.

## `00-功能总览.md`

Stable entry point: conclusion, goal, scope/non-goals, current behavior,
status, key entry points, evidence map, open questions, and risks. Keep it
readable as an entry point; put deep call-chain detail in `01-实现细节.md`.

## Project-level notes

`<project>/00-项目总览.md` uses `type: code-project-overview`,
`schema_version`, `note_kind: project-overview`, `project`, `review`,
`updated`, `audience`, `detail_level`, `capture_mode`, `source_commit`, and
`tags`. It is a compact,
beginner-friendly entry point containing purpose, suggested reading order,
minimal run/debug guidance, architecture, status, risks, and feature links; it
must not duplicate the detailed feature notes.

`<project>/01-架构与术语.md` uses `type: code-project-architecture`,
`schema_version`, `note_kind: project-architecture`, `project`, `review`,
`updated`, `audience`, `detail_level`, `capture_mode`, `source_commit`, and
`tags`. It records the
system boundary, components, numbered data/control flow, invariants, a
project-grounded glossary, compatibility assumptions, and evidence. It is
created or updated only when architecture evidence exists.

## `01-实现细节.md`

Problem context, symptom and impact, goals/non-goals, old behavior, a guided
end-to-end call chain, data/control flow, state/invariants, decisions and
alternatives, data structures, changed files, edge cases, compatibility notes,
observability, and rollback/recovery considerations. Explain the important
syntax around each excerpt and record facts with paths or symbols.

## `02-实施效果.md`

Before/after behavior, scenario-based verification, test and build results,
artifact identifiers, performance or regression signals, screenshots or logs,
rollout/rollback evidence, and unverified boundaries. Never convert “build
succeeded” into “user scenario verified.”

## `03-知识应用总结.md`

Generalizable patterns, feature-specific terms, debugging lessons, reusable
design decisions, failure modes, anti-patterns, a compact “how to apply”
recipe, transfer conditions, explain-back questions, and safe exercises with
expected observations.

## `04-后续迭代方向.md`

P0/P1/P2 improvements with rationale, acceptance criteria, dependencies, risk,
owner or scope when known, and whether the item is a follow-up idea or an
already-started task.

## `99-相关对话与文件.md`

Source thread IDs, repository paths, reports, artifacts, commits, commands,
test outputs, and related Obsidian notes. For each important claim, record the
source type, location, relevance, and confidence. Redact credentials and
personal data.

## Code evidence contract

Every code example should carry these fields:

- `File`: source file path.
- `Symbol/line`: function, class, configuration key, test name, or line location.
- `Role`: what behavior the example proves or explains.
- `Source`: a short fenced block copied from the repository.
- `Why it matters`: the connection between the source and the captured knowledge.
- `Input`: the value/event arriving and where it came from.
- `Processing`: the important statements and any essential syntax.
- `Mechanism`: why the processing changes data, control flow, or state and
  which condition enables it.
- `Output/side effect`: what leaves or changes and who consumes it next.
- `Failure signal`: what the reader could observe if this step failed.
- `Counterfactual/boundary`: what changes if a key statement/condition is
  removed or altered, and which part is `未验证`.

## Project overview rule

`00-项目总览.md` is a compact index, not a duplicate of every feature note. It should list the project purpose, architecture, feature status matrix, current risks, and links to feature directories.

Project and feature IDs must comply with [path-policy.md](path-policy.md). Before writing, candidates must comply with [redaction-policy.md](redaction-policy.md); a secret scan failure is a blocked write, not a warning.
