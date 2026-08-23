# Platform support

## Supported workflow

| Surface | Status | Notes |
|---|---|---|
| Codex Desktop/CLI on Windows | Supported | PowerShell bootstrap, doctor, and lifecycle scripts |
| Codex Desktop/CLI on macOS | Supported | Bash/JXA bootstrap, doctor, and lifecycle scripts |
| Codex IDE extension with local MCP access | Expected | Uses the same local Codex configuration; run doctor first |
| Linux/WSL | Not currently supported | Obsidian discovery and lifecycle scripts are not implemented |
| ChatGPT web/mobile | Not supported for writes | The required Obsidian endpoint is bound to the user's local loopback interface |
| Codex cloud/remote environments | Not supported for writes | They cannot reach the desktop's `127.0.0.1` endpoint without a separately designed secure tunnel |

The plugin package is intentionally local-first even though plugin packages may
be discoverable on multiple product surfaces. Unsupported surfaces may still
read the Skill description, but they must not claim an Obsidian write succeeded.

## Future remote support

Remote or universal write support would require a separately reviewed MCP
deployment with user authentication, scoped authorization, transport security,
retention/deletion policies, and explicit consent. The current loopback bearer
key must not be reused as a remote credential.
