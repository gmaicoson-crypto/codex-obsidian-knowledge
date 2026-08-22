# Codex Obsidian Knowledge setup

When this repository is opened on a user's Windows or macOS machine, check whether the Obsidian integration is ready before using the knowledge-capture workflow.

If the integration is not ready:

1. Explain that setup will download the third-party `Local REST API with MCP` Obsidian plugin, modify the selected Obsidian vault's local plugin settings, create an API key, and update Codex's user MCP configuration.
2. Ask the user for confirmation before running any setup command. Do not install or configure third-party software silently.
3. After confirmation, run `scripts/bootstrap.ps1 -Approve` on Windows or `bash scripts/bootstrap.sh --approve` on macOS. If the Obsidian vault cannot be uniquely discovered, ask the user for its absolute path and pass it with `-VaultPath` or `--vault`.
4. Ask the user to restart Obsidian once if the endpoint is not reachable, then restart Codex and run the matching doctor script.

Use the connected Obsidian MCP only after the doctor check succeeds. Keep the existing preview-first and explicit confirmation workflow for writing notes. Never print or commit the Local REST API API key.
