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

if ! command -v osascript >/dev/null 2>&1; then
  printf '%s\n' 'osascript was not found; macOS JSON manifest parsing is required.' >&2
  exit 1
fi
json_field() {
  local path="$1" field="$2"
  JSON_PATH="$path" JSON_FIELD="$field" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const path = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('JSON_PATH'));
const field = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('JSON_FIELD'));
  const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
  const data = JSON.parse(raw.replace(/^\uFEFF/, ''));
data[field] !== undefined && data[field] !== null ? String(data[field]) : '';
JXA
}
plugin_name="$(json_field "$manifest_path" name)"
marketplace_name="$(json_field "$marketplace_path" name)"
if [[ -z "$plugin_name" || -z "$marketplace_name" ]]; then
  printf '%s\n' 'Plugin or marketplace manifest is missing its name.' >&2
  exit 1
fi
[[ "$plugin_name" =~ ^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$ ]] || { printf 'Invalid plugin name in manifest: %s\n' "$plugin_name" >&2; exit 1; }
[[ "$marketplace_name" =~ ^[A-Za-z0-9_-]+$ ]] || { printf 'Invalid marketplace name in manifest: %s\n' "$marketplace_name" >&2; exit 1; }
plugin_selector="$plugin_name@$marketplace_name"
bash "$repo_root/scripts/build-plugin-package.sh" >/dev/null
user_codex_root="${CODEX_HOME:-$HOME/.codex}"
cache_path="$user_codex_root/plugins/cache/$marketplace_name/$plugin_name/local"

if ! plugins="$(codex plugin list 2>&1)"; then
  printf '%s\n' 'Could not inspect installed Codex plugins. No files or configuration were changed.' >&2
  printf '%s\n' "$plugins" >&2
  exit 1
fi
plugin_already_installed=0
if printf '%s\n' "$plugins" | awk -v selector="$plugin_selector" '$1 == selector && $2 ~ /^installed/ { found=1 } END { exit !found }'; then plugin_already_installed=1; fi
if [[ "$plugin_already_installed" -eq 0 && -e "$cache_path" ]]; then
  printf 'Plugin cache path already exists and is not reported as this installed plugin: %s. Refusing to overwrite it.\n' "$cache_path" >&2
  exit 1
fi

if ! marketplaces="$(codex plugin marketplace list 2>&1)"; then
  printf '%s\n' 'Could not inspect configured Codex marketplaces. No files or configuration were changed.' >&2
  printf '%s\n' "$marketplaces" >&2
  exit 1
fi
marketplace_added_by_this_run=0
marketplace_line="$(printf '%s\n' "$marketplaces" | awk -v name="$marketplace_name" '$1 == name { print; exit }')"
if [[ -z "$marketplace_line" ]]; then
  printf 'Registering repository marketplace: %s\n' "$marketplace_name"
  codex plugin marketplace add "$repo_root"
  marketplace_added_by_this_run=1
else
  if ! printf '%s\n' "$marketplace_line" | grep -Fq "$repo_root"; then
    printf "Marketplace '%s' already exists at a different location. No files or configuration were changed.\n" "$marketplace_name" >&2
    exit 1
  fi
  printf 'Repository marketplace is already registered: %s\n' "$marketplace_name"
fi

if [[ "$plugin_already_installed" -eq 1 ]]; then
  printf 'Plugin is already installed: %s\n' "$plugin_selector"
else
  printf 'Installing plugin: %s\n' "$plugin_selector"
  if ! codex plugin add "$plugin_selector"; then
    if [[ "$marketplace_added_by_this_run" -eq 1 ]]; then
      if codex plugin marketplace remove "$marketplace_name"; then
        printf 'Rolled back marketplace registration: %s\n' "$marketplace_name"
      else
        printf "Plugin installation failed and marketplace rollback also failed. Remove '%s' manually.\n" "$marketplace_name" >&2
      fi
    fi
    exit 1
  fi
fi

printf '%s\n' 'Codex plugin installation is complete.'
printf '%s\n' 'Restart Codex and test the skill in a new conversation.'
