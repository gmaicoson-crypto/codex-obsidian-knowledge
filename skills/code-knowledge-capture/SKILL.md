---
name: code-knowledge-capture
description: Summarize a code discussion or implementation into a reviewable project-and-feature knowledge set in Obsidian. Use when the user explicitly asks to summarize, distill, archive, or write coding knowledge after review; do not use for ordinary code changes.
metadata:
  short-description: Preview and capture code knowledge in Obsidian
---

# Code Knowledge Capture

Turn a completed or discussed coding task into durable, source-linked knowledge in Obsidian. This skill is project-agnostic: infer the project and feature from the current repository and conversation, and never hard-code a project name or local vault path.

Before choosing note paths, look for the integration settings file `.codex-obsidian-knowledge.json` at the Vault root through the connected Obsidian MCP. If it exists, use its `noteRoot` value as a relative path prefix. If it is absent or empty, use the Vault root. Never treat an absolute path or a `..` segment as a valid note root.

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
2. Show the project, feature, status, target paths, facts, uncertainties, and proposed updates.
3. Write only after the user says “确认写入” or gives an equivalent explicit approval.
4. If the user requests a change, regenerate the preview; do not silently write.

“取消” stops the workflow. Existing notes are never deleted. Updating an existing project or feature overview always appears in the preview.

## Evidence collection

Before the preview, use read-only inspection where available:

- Current conversation messages and final decisions.
- Repository root, project identity, and relevant changed files.
- `git diff`, test commands and results, build reports, artifacts, and deployment evidence.
- Existing project/feature notes in Obsidian for merge and duplicate detection.

Do not modify source code, run destructive commands, or expose secrets during capture. Treat a design or plan as design; treat code as implemented only when a file change is evidenced; treat it as verified only when the relevant test or build evidence exists.

Use these statuses:

- `analysis`: investigation only
- `design`: proposed solution only
- `implemented`: code or configuration changed
- `verified`: implementation plus relevant verification evidence
- `blocked`: progress stopped by a named blocker

Read [summary-schema.md](references/summary-schema.md) when drafting the note structure and [review-policy.md](references/review-policy.md) when deciding whether an update needs confirmation or how to handle sensitive evidence.

## Obsidian write contract

Use the connected Obsidian MCP server after approval. Prefer its structured vault read/write/patch/search tools; do not fall back to arbitrary local file writes when the MCP connection is unavailable. If the required MCP capability is missing, report the exact setup issue and do not claim that anything was written.

The canonical layout, relative to the configured note root, is:

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

Create a feature directory for a new feature. For an existing feature, preview a patch to the affected notes rather than replacing the whole directory. Keep implementation details, evidence, reusable knowledge, and future work separate. Update the project overview only with stable conclusions and confirmed status.

After writing, read back the changed notes or use the MCP response to verify paths and report exactly what changed.
