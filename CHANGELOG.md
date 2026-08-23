# Changelog

## Unreleased

## 0.3.0 - 2026-08-23

- Refocused the plugin on beginning programmers who use Codex to write code,
  with learning goals, prerequisites, plain-language mental models, and
  project-grounded terminology.
- Added three-level architecture explanations, guided input-to-output code
  walkthroughs, syntax and failure-signal annotations, debugging paths,
  explain-back questions, and safe exercises with expected observations.
- Added `audience: beginner-programmer` metadata while preserving compatibility
  with existing notes that do not yet contain the field.
- Expanded the default knowledge-capture mode with evidence maps, end-to-end
  flows, decision trade-offs, verification boundaries, reusable lessons, and
  acceptance criteria for follow-up work.
- Added `detail_level: expanded` to the note templates while keeping older
  notes compatible with incremental updates.
- Added compact, expanded, architecture-only, and update-only capture modes.
- Added schema version 2 metadata with note kinds, stable capture IDs, evidence
  hashes, source commits, and verification timestamps.
- Reconciled the Local REST API HTTP server setting in both directions and made
  doctor detect or explicitly repair protocol-state drift.
- Added conservative API-key rotation, disconnect, and uninstall workflows for
  Windows and macOS; knowledge notes are never removed by uninstall.
- Added representative Skill behavior cases, opt-in live Codex evaluations,
  isolated Codex CLI package tests, and temporary-Vault lifecycle tests.
- Pinned GitHub Actions by commit, added release packaging, and added a weekly
  upstream-release and pinned-asset watcher.
- Added plugin artwork, a demo, platform support boundaries, maintainer links,
  and a local-first privacy policy.
- Added marketplace rollback when plugin installation fails.

## 0.2.0 - 2026-08-22

- Added pinned SHA-256 verification for the upstream Local REST API assets.
- Made Windows and macOS bootstrap/configuration changes staged and rollback-capable.
- Unified `CODEX_HOME` resolution and hardened MCP configuration parsing.
- Added plugin identity/version checks, explicit HTTP fallback checks, and stronger doctor handshakes.
- Added note path and sensitive-content policies, a local sensitive-content scanner, and project architecture templates.
- Added Windows and macOS repository validation paths.
- Fixed Windows single-plugin JSON array handling and matching doctor checks.
- Protected the macOS PowerShell `.zshenv` credential file with owner-only permissions.
- Added standalone provider-key and high-entropy token detection before note writes.
- Enforced the complete 240-character note-path limit and bounded Windows MCP diagnostics.
