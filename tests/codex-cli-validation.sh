#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
command -v codex >/dev/null 2>&1 || { echo 'Codex CLI is required for plugin package validation.' >&2; exit 1; }
command -v osascript >/dev/null 2>&1 || { echo 'osascript is required for macOS manifest parsing.' >&2; exit 1; }

json_field() {
  JSON_PATH="$1" JSON_FIELD="$2" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const jsonPath = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('JSON_PATH'));
const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(jsonPath, $.NSUTF8StringEncoding, null));
const data = JSON.parse(raw.replace(/^\uFEFF/, ''));
const jsonField = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('JSON_FIELD'));
String(data[jsonField]);
JXA
}

plugin_name="$(json_field "$repo_root/.codex-plugin/plugin.json" name)"
marketplace_name="$(json_field "$repo_root/.agents/plugins/marketplace.json" name)"
selector="$plugin_name@$marketplace_name"
temporary_root="${TMPDIR:-/tmp}"
temporary_root="${temporary_root%/}"
temporary_codex_home="$(mktemp -d "$temporary_root/codex-plugin-validation.XXXXXX")"
previous_codex_home="${CODEX_HOME-}"
cleanup() {
  local status=$?
  if [[ -n "$previous_codex_home" ]]; then export CODEX_HOME="$previous_codex_home"; else unset CODEX_HOME || true; fi
  if [[ "$temporary_codex_home" == "$temporary_root/codex-plugin-validation."* ]]; then
    rm -rf -- "$temporary_codex_home"
  else
    echo "Refusing to clean unexpected temporary Codex Home: $temporary_codex_home" >&2
  fi
  return "$status"
}
trap cleanup EXIT
export CODEX_HOME="$temporary_codex_home"

if ! bash "$repo_root/scripts/install-plugin.sh" --approve >/dev/null; then
  echo 'Initial plugin installation failed in the isolated Codex Home.' >&2
  exit 1
fi
if ! plugins="$(codex plugin list --marketplace "$marketplace_name" 2>&1)"; then
  echo 'Could not list the installed test plugin.' >&2
  printf '%s\n' "$plugins" >&2
  exit 1
fi
if ! printf '%s\n' "$plugins" | awk -v selector="$selector" '$1 == selector && $2 ~ /^installed/ { found=1 } END { exit !found }'; then
  echo "Codex CLI did not report the isolated plugin as installed: $selector" >&2
  printf '%s\n' "$plugins" >&2
  exit 1
fi
if ! bash "$repo_root/scripts/install-plugin.sh" --approve >/dev/null; then
  echo 'Plugin installer was not idempotent in the isolated Codex Home.' >&2
  exit 1
fi
if ! remove_output="$(codex plugin remove "$selector" 2>&1)"; then
  echo "Codex CLI could not remove the isolated test plugin: $selector" >&2
  printf '%s\n' "$remove_output" >&2
  exit 1
fi
if ! remove_marketplace_output="$(codex plugin marketplace remove "$marketplace_name" 2>&1)"; then
  echo "Codex CLI could not remove the isolated test marketplace: $marketplace_name" >&2
  printf '%s\n' "$remove_marketplace_output" >&2
  exit 1
fi
echo 'Codex CLI plugin package validation passed.'
