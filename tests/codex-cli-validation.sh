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
temporary_codex_home="$(mktemp -d "${TMPDIR:-/tmp}/codex-plugin-validation.XXXXXX")"
previous_codex_home="${CODEX_HOME-}"
cleanup() {
  if [[ -n "$previous_codex_home" ]]; then export CODEX_HOME="$previous_codex_home"; else unset CODEX_HOME || true; fi
  [[ "$temporary_codex_home" == "${TMPDIR:-/tmp}/codex-plugin-validation."* ]] && rm -rf -- "$temporary_codex_home"
}
trap cleanup EXIT
export CODEX_HOME="$temporary_codex_home"

bash "$repo_root/scripts/install-plugin.sh" --approve >/dev/null
codex plugin list | grep -Eq "^[[:space:]]*${selector}[[:space:]]+installed"
bash "$repo_root/scripts/install-plugin.sh" --approve >/dev/null
codex plugin remove "$selector" >/dev/null
codex plugin marketplace remove "$marketplace_name" >/dev/null
echo 'Codex CLI plugin package validation passed.'
