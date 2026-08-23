# Codex Obsidian Knowledge setup

## Install this repository as a Codex plugin

This repository is itself a Codex plugin. If the user provides this local folder or a repository URL and explicitly asks to add, install, or enable it as a Codex plugin:

1. If the repository came from a URL, make sure it is checked out locally and work from the checked-out repository root.
2. Explain that installation will generate an ignored standard plugin package under `plugins/codex-obsidian-knowledge`, register this repository as a local Codex marketplace, and update the current user's Codex configuration and plugin cache.
3. After the user's confirmation, run `scripts/install-plugin.ps1 -Approve` on Windows or `bash scripts/install-plugin.sh --approve` on macOS.
4. Ask the user to restart Codex and test the plugin in a new conversation.

The installer must be conservative with existing user state. If the marketplace name already points to another location, or the target plugin cache path already exists without being reported as this installed plugin, stop and report the conflict. Never overwrite, delete, or replace an existing user plugin or cache directory. Do not run the installer merely because the repository was opened for code review or inspection. Do not manually copy the repository into `.codex/plugins`; the installer uses the repository's `.agents/plugins/marketplace.json` and the Codex plugin CLI.

If plugin installation fails after this run added the marketplace, the installer may remove only that marketplace registration as rollback. It must not remove a marketplace that existed before the run.

When this repository is opened on a user's Windows or macOS machine, check whether the Obsidian integration is ready before using the knowledge-capture workflow.

If the integration is not ready:

1. Explain that setup will download the third-party `Local REST API with MCP` Obsidian plugin, modify the selected Obsidian vault's local plugin settings, create an API key, and update Codex's user MCP configuration.
2. Ask the user for confirmation before running any setup command. Do not install or configure third-party software silently.
3. After confirmation, run `scripts/bootstrap.ps1 -Approve` on Windows or `bash scripts/bootstrap.sh --approve` on macOS. If the Obsidian vault cannot be uniquely discovered, ask the user for its absolute path and pass it with `-VaultPath` or `--vault`.
4. Ask the user to restart Obsidian once if the endpoint is not reachable, then restart Codex and run the matching doctor script.

Use the connected Obsidian MCP only after the doctor check succeeds. Keep the existing preview-first and explicit confirmation workflow for writing notes. Never print or commit the Local REST API API key.

Key rotation, disconnect, doctor repair, and uninstall are separate explicit maintenance actions. Explain their scope and obtain confirmation before running the matching script. Disconnect and uninstall must preserve Markdown knowledge notes; uninstall may remove only the selected Vault's Local REST API plugin files and integration settings.
