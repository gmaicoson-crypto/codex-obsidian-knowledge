# Privacy policy

## Scope

Codex Obsidian Knowledge is a local-first Codex plugin. It supplies a Skill,
templates, and setup scripts. The project does not operate a hosted server,
receive Vault contents, or maintain a project-owned analytics database.

## Data flow

When the user explicitly requests knowledge capture, Codex may process the
current conversation, selected repository evidence, test/build results, and
existing target notes. Model processing follows the privacy and retention
terms of the Codex/OpenAI product and account used by the user. This repository
does not change those terms.

Approved notes are sent over an authenticated loopback MCP connection to the
third-party Obsidian community plugin `Local REST API with MCP` and stored as
Markdown in the selected Vault. HTTPS is preferred. The explicit HTTP fallback
is restricted to `127.0.0.1` and still requires a bearer key.

## Local storage

The integration may store:

- learning notes in the user-selected Obsidian Vault;
- `.codex-obsidian-knowledge.json` in that Vault for the relative note root;
- the Local REST API key in the Obsidian plugin's `data.json`;
- the same key in the Windows user environment or a marked macOS `.zshenv`
  block unless secret import is disabled;
- an `[mcp_servers.obsidian]` section in the user's Codex configuration.

The key value is not intentionally printed, committed, or written into notes.
Candidate notes must be redacted and scanned before an approved write.

## Retention and deletion

The project has no server-side retention because it operates no server.
Obsidian notes remain until the user deletes them. `disconnect` removes the
Codex connection while preserving plugin files and notes. `uninstall` removes
the selected Vault's third-party plugin files and integration settings while
preserving knowledge notes. `rotate-key` replaces the local API key.

## Third parties

First-run setup downloads the pinned `Local REST API with MCP` release from its
upstream GitHub repository and verifies repository-pinned SHA-256 values. That
plugin is maintained by its upstream authors and has its own policies.

## Security reports and questions

Use the repository's GitHub Security Advisories channel for vulnerabilities.
Use GitHub Issues for non-sensitive privacy questions. Never include keys,
private Vault contents, or raw confidential conversations in a report.
