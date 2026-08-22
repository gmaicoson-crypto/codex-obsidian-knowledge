# Security policy

## Supported versions

Security fixes are applied to the latest version on the default branch. The project currently uses a pinned `Local REST API with MCP` dependency; changes to that dependency require asset hash and manifest review.

## Reporting a vulnerability

Do not include API keys, bearer tokens, cookies, private keys, or complete Vault contents in a public issue. Report the affected file, impact, reproduction conditions using synthetic values, and a proposed mitigation through the repository's private security-reporting channel when one is available.

## Scope

Reports involving the bootstrap scripts, MCP configuration boundary, note-path handling, credential handling, and preview/write safety are in scope. The third-party Obsidian plugin itself is maintained upstream and should be reported to its maintainers after confirming the issue is not introduced by this repository.
