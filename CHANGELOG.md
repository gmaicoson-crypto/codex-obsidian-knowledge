# Changelog

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
