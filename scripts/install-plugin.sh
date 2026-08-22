#!/usr/bin/env bash
set -euo pipefail

approve=false
for argument in "$@"; do
  case "$argument" in
    --approve)
      approve=true
      ;;
    *)
      printf 'Unknown argument: %s\n' "$argument" >&2
      exit 2
      ;;
  esac
done

if [[ "$approve" != true ]]; then
  printf '%s\n' 'Plugin installation changes the current user Codex configuration and plugin cache. Re-run with --approve after the user confirms.' >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  printf '%s\n' 'Codex CLI was not found on PATH. Open this repository from a Codex installation and try again.' >&2
  exit 1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
manifest_path="$repo_root/.codex-plugin/plugin.json"
marketplace_path="$repo_root/.agents/plugins/marketplace.json"

if [[ ! -f "$manifest_path" ]]; then
  printf 'Plugin manifest not found: %s\n' "$manifest_path" >&2
  exit 1
fi
if [[ ! -f "$marketplace_path" ]]; then
  printf 'Marketplace manifest not found: %s\n' "$marketplace_path" >&2
  exit 1
fi

plugin_name='codex-obsidian-knowledge'
marketplace_name='codex-obsidian-knowledge-repo'
plugin_selector="$plugin_name@$marketplace_name"
user_codex_root="${CODEX_HOME:-$HOME/.codex}"
cache_path="$user_codex_root/plugins/cache/$marketplace_name/$plugin_name/local"

if ! marketplaces="$(codex plugin marketplace list 2>&1)"; then
  printf '%s\n' 'Could not inspect configured Codex marketplaces. No files or configuration were changed.' >&2
  exit 1
fi
if ! printf '%s\n' "$marketplaces" | grep -Fq "$marketplace_name"; then
  printf 'Registering repository marketplace: %s\n' "$marketplace_name"
  codex plugin marketplace add "$repo_root"
else
  marketplace_line="$(printf '%s\n' "$marketplaces" | grep -F "$marketplace_name" | head -n 1)"
  if ! printf '%s\n' "$marketplace_line" | grep -Fq "$repo_root"; then
    printf "Marketplace '%s' already exists at a different location. No files or configuration were changed.\n" "$marketplace_name" >&2
    exit 1
  fi
  printf 'Repository marketplace is already registered: %s\n' "$marketplace_name"
fi

if ! plugins="$(codex plugin list 2>&1)"; then
  printf '%s\n' 'Could not inspect installed Codex plugins. No files or configuration were changed.' >&2
  exit 1
fi
if printf '%s\n' "$plugins" | grep -Eq "^[[:space:]]*${plugin_selector}[[:space:]]+installed"; then
  printf 'Plugin is already installed: %s\n' "$plugin_selector"
elif [[ -e "$cache_path" ]]; then
  printf 'Plugin cache path already exists and is not reported as this installed plugin: %s. Refusing to overwrite it.\n' "$cache_path" >&2
  exit 1
else
  printf 'Installing plugin: %s\n' "$plugin_selector"
  codex plugin add "$plugin_selector"
fi

printf '%s\n' 'Codex plugin installation is complete.'
printf '%s\n' 'Restart Codex and test the skill in a new conversation.'
