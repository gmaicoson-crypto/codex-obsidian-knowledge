---
name: code-knowledge-capture
description: Turn a code discussion or Codex implementation into a reviewable, beginner-friendly project-and-feature learning set in Obsidian. Use when the user explicitly asks to capture, distill, archive, or write coding work as learning notes; do not use for ordinary code changes or one-off code explanations.
metadata:
  short-description: Learn from Codex-written code in Obsidian
---

# Code Knowledge Capture

Turn a completed or discussed coding task into durable, source-linked learning material in Obsidian. The primary reader is a beginning programmer who uses Codex to build software and wants to understand the resulting code instead of merely storing a change log. The notes must help that reader answer: what is this, why is it needed, how does it work, where is it implemented, how was it verified, and how can I recognize or reuse the idea later?

This skill is project-agnostic: infer the project and feature from the current repository and conversation, and never hard-code a project name or local vault path.

Before choosing note paths, look for the integration settings file `.codex-obsidian-knowledge.json` at the Vault root through the connected Obsidian MCP. If it exists, use its `noteRoot` value as a relative path prefix. If it is absent or empty, use the Vault root. Never treat an absolute path or a `..` segment as a valid note root.

Read [path-policy.md](references/path-policy.md) and [redaction-policy.md](references/redaction-policy.md) before drafting targets or content. Project IDs, feature IDs, note paths, and sensitive-content handling must follow those references.

Use `expanded` capture by default. If the user requests `compact`,
`architecture-only`, or `update-only`, or if you recommend compact capture for
a small task, read [capture-modes.md](references/capture-modes.md). Always show
the selected mode and omitted notes in the preview; never silently reduce the
capture set.

## First-run connection

If the Obsidian MCP server is unavailable and this repository is present as the user's project, use the repository's cross-platform bootstrap flow before attempting any note read or write:

- Windows: explain the third-party download and configuration changes, obtain confirmation, then run `scripts/bootstrap.ps1 -Approve`.
- macOS: explain the same changes, obtain confirmation, then run `bash scripts/bootstrap.sh --approve`.

If the Vault cannot be uniquely discovered, ask for its absolute path and pass it to the bootstrap script. Do not print the API key. Do not claim the connection is ready until the corresponding doctor script succeeds after Obsidian has loaded the plugin.

## Invocation and approval

Use this skill only when the user explicitly requests knowledge capture, for example:

- “将本次代码对话进行知识总结沉淀。”
- “总结本次功能开发并写入 Obsidian。”
- “先预览这次实现的知识卡片。”

Default scope is the current conversation and current project. If the project or feature is ambiguous, ask one concise question before drafting. Do not read unrelated conversations unless the user names them.

The workflow is review-first:

1. Collect evidence and draft a preview without modifying files.
2. Show the project, feature, status, capture mode, target paths, identity fields, facts, uncertainties, omissions, and proposed updates.
3. Write only after the user says “确认写入” or gives an equivalent explicit approval.
4. If the user requests a change, regenerate the preview; do not silently write.

“取消” stops the workflow. Existing notes are never deleted. Updating an existing project or feature overview always appears in the preview.

## Evidence collection

Before the preview, use read-only inspection where available:

- Current conversation messages and final decisions.
- Repository root, project identity, and relevant changed files.
- `git diff`, test commands and results, build reports, artifacts, and deployment evidence.
- Existing project/feature notes in Obsidian for merge and duplicate detection.

Do not modify source code, run destructive commands, or expose secrets during capture. Treat a design or plan as design; treat code as implemented only when a file change is evidenced. Use `verified` only when the evidence covers the claimed runtime or user scenario; passing tests or a build without that scenario remains `implemented` with an explicit verification boundary, as defined in [review-policy.md](references/review-policy.md).

Immediately before an approved write, validate the complete target path and scan the candidate Markdown for sensitive content. When a local candidate file can be materialized, use `scripts/scan-sensitive-content.ps1`; otherwise perform the same rule-based scan and report that the MCP write was not locally scanner-verified. A detected credential blocks the write until the preview is redacted.

For a new project or feature, use `scripts/validate-note-path.ps1` when available to validate the Vault, note root, project ID, and feature ID before invoking the MCP write.

Use these statuses:

- `analysis`: investigation only
- `design`: proposed solution only
- `implemented`: code or configuration changed
- `verified`: implementation plus evidence for the claimed runtime or user scenario
- `blocked`: progress stopped by a named blocker

Read [summary-schema.md](references/summary-schema.md) when drafting the note
structure and capture identity. Build its redacted canonical evidence manifest,
compute `evidence_hash`, and derive `capture_id` before duplicate detection.
When the repository helpers are available, use
`scripts/new-evidence-identity.ps1` on Windows or
`scripts/new-evidence-identity.sh` on macOS instead of inventing an identity.
Record `source_commit` when Git provides it and set `verified_at` only when the
verification status is `verified`. Read
[beginner-learning-guide.md](references/beginner-learning-guide.md) when
creating explanations and learning checks. Read
[deep-exploration-guide.md](references/deep-exploration-guide.md) when the
capture mode is `expanded` (the default), the user asks for a deep/in-depth
summary, or the evidence contains a non-trivial mechanism, failure mode, or
design trade-off. The deep-exploration guide is the completeness gate: do not
equate a populated template, a glossary, or a file list with understanding.
Read
[review-policy.md](references/review-policy.md) when deciding whether an update
needs confirmation or how to handle sensitive evidence.

## Beginner-first expanded capture mode

The default metadata is `schema_version: 2`,
`audience: beginner-programmer`, `capture_mode: expanded`, and
`detail_level: expanded`. “Beginner-first” does not mean removing technical
accuracy. Explain each important idea in two layers: a plain-language mental
model first, then the exact code, symbol, data flow, or test evidence. Define a
term at first use, explain unfamiliar syntax that matters to the behavior, and
connect every code excerpt to its input, processing, output, and role in the
larger flow.

Do not pad notes with generic prose or turn them into a line-by-line dump. Teach
only concepts supported by the task evidence and needed to understand this
project. When evidence is missing, write `未验证`, `无证据`, or `[待确认]` and
identify the missing check.

Before drafting, build an evidence map with these buckets:

| Bucket | Required questions |
|---|---|
| Context | What symptom or goal triggered the work? What is in and out of scope? |
| Behavior | What happened before, what happens now, and what invariant must hold? |
| Structure | Which entry point, call chain, data flow, state transition, and boundary explain it? |
| Decisions | Which alternatives were considered, and what trade-off selected the approach? |
| Implementation | Which files, symbols, configuration keys, and tests prove the change? |
| Verification | Which checks passed, what scenario was exercised, and what remains unverified? |
| Reuse | What rule, failure mode, debugging method, or anti-pattern transfers elsewhere? |
| Follow-up | What should happen next, with priority, acceptance criteria, and dependencies? |

For every material conclusion, also answer the depth chain: what is the
mechanism between input and result, what evidence supports each transition,
what changes under a relevant counterfactual, where the mechanism fails, and
when the lesson transfers. A list of terms, files, or conclusions without this
chain is incomplete even when every template heading has content.

Also build a learning map:

| Learning bucket | Required questions |
|---|---|
| Prerequisites | What should the reader know first, and what can be learned inline? |
| Vocabulary | Which key terms or syntax appear, what do they mean plainly, and where do they appear in this project? |
| Mental model | What small model lets the reader predict the feature before reading details? |
| Guided walkthrough | How does one concrete input travel from entry point to output, including an error path? |
| Debugging | What should the reader observe first, and how can they narrow a failure safely? |
| Self-check | What explain-back questions and small, safe exercises demonstrate understanding? |

Use `[事实]`, `[推断]`, `[计划]`, and `[待确认]` when a reader could confuse
evidence with interpretation or future work. The preview must expose the
evidence map, reader prerequisites, key terms, at least one end-to-end flow,
the main decision/trade-off, the verification boundary, the proposed
self-checks, and a **深度探究审计** before any write. The audit must map each
core question to its mechanism, source evidence, counterfactual or failure
path, evidence boundary, and reuse condition. Mark missing evidence instead of
filling it with generic explanation.

## Concrete code examples are required

For implemented code, knowledge capture must include concrete source examples instead of only prose:

- Include 1–3 short, representative snippets for the entry point, core logic, or validation/test path.
- Each snippet must identify the file path, symbol or line location, programming language, and why the code matters to the observed behavior.
- Quote the actual source with a fenced code block; do not silently replace source with pseudocode. Use `...` only to omit irrelevant surrounding lines.
- Prefer a before/after comparison when the behavior changed, and distinguish production code from test code.
- If the item is design-only, configuration-only, or depends entirely on external code, explicitly record `无可引用代码实例` and explain the evidence boundary.

The preview for an implemented feature must show at least one code example or the explicit no-example explanation before any note is written.

For an expanded implementation note, prefer 1–3 snippets that cover different
roles: entry point, core transformation or state change, and validation/test.
Do not repeat the same snippet in every note; link back to the implementation
note when the source is unchanged. If a snippet cannot be safely quoted, record
the file and symbol plus `无可引用代码实例`, explain the evidence boundary, and
keep secrets redacted.

## Obsidian write contract

Use the connected Obsidian MCP server after approval. Prefer its structured vault read/write/patch/search tools; do not fall back to arbitrary local file writes when the MCP connection is unavailable. If the required MCP capability is missing, report the exact setup issue and do not claim that anything was written. A matching `capture_id` or `evidence_hash` with no content delta is a successful no-op, not a reason to duplicate notes.

The canonical expanded layout, relative to the configured note root, is:

```text
<project>/
├── 00-项目总览.md
├── 01-架构与术语.md
└── features/<feature>/
    ├── 00-功能总览.md
    ├── 01-实现细节.md
    ├── 02-实施效果.md
    ├── 03-知识应用总结.md
    ├── 04-后续迭代方向.md
    └── 99-相关对话与文件.md
```

For example, when `noteRoot` is `Codex知识库`, the project overview is written to `Codex知识库/<project>/00-项目总览.md` relative to the Vault.

Create a feature directory for a new feature only when the selected capture mode includes feature notes. For an existing feature, preview a patch to the affected notes rather than replacing the whole directory. `update-only` must stop at preview when the target does not exist. Keep implementation details, evidence, reusable knowledge, and future work separate. Update the project overview only with stable conclusions and confirmed status.

Use safe slug IDs for `<project>` and `<feature>` and retain display names in frontmatter/headings. Validate every generated path segment immediately before the MCP operation; do not let Markdown, wikilinks, or user text introduce extra path components.

After writing, read back the changed notes or use the MCP response to verify paths and report exactly what changed.
