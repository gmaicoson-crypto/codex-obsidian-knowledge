#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
METADATA_PATH="$SCRIPT_DIR/upstream-assets.json"
VAULT_PATH=""
CODEX_CONFIG_PATH="${CODEX_HOME:-$HOME/.codex}/config.toml"
ALLOW_INSECURE_HTTP=0
REPAIR=0
APPROVED=0
SECRET_ENV_NAME='OBSIDIAN_LOCAL_REST_API_KEY'
failures=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault) VAULT_PATH="${2:?Missing value for --vault}"; shift 2 ;;
    --codex-config) CODEX_CONFIG_PATH="${2:?Missing value for --codex-config}"; shift 2 ;;
    --allow-insecure-http) ALLOW_INSECURE_HTTP=1; shift ;;
    --repair) REPAIR=1; shift ;;
    --approve) APPROVED=1; shift ;;
    -h|--help) echo 'Usage: ./scripts/doctor.sh --vault /absolute/path/to/vault [--allow-insecure-http] [--repair --approve]'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

check() {
  local name="$1" passed="$2" detail="$3"
  if [[ "$passed" == '1' ]]; then printf '[OK]   %s: %s\n' "$name" "$detail"
  else printf '[FAIL] %s: %s\n' "$name" "$detail"; failures=$((failures + 1)); fi
}

load_metadata() {
  [[ -f "$METADATA_PATH" ]] || { check 'Asset metadata' 0 "$METADATA_PATH"; return; }
  local lines
  if ! lines="$(METADATA_PATH="$METADATA_PATH" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const path = $.getenv('METADATA_PATH');
  const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
  const data = JSON.parse(raw.replace(/^\uFEFF/, ''));
console.log(data.pluginId); console.log(data.version);
JXA
)"; then check 'Asset metadata' 0 'Could not parse upstream-assets.json'; return; fi
  PLUGIN_ID="$(printf '%s\n' "$lines" | sed -n '1p')"
  PLUGIN_VERSION="$(printf '%s\n' "$lines" | sed -n '2p')"
  check 'Asset metadata' $([[ -n "$PLUGIN_ID" && -n "$PLUGIN_VERSION" ]] && echo 1 || echo 0) "$METADATA_PATH"
}

json_field() {
  local path="$1" field="$2"
  JSON_PATH="$path" JSON_FIELD="$field" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const path = $.getenv('JSON_PATH');
const field = $.getenv('JSON_FIELD');
  const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
  const data = JSON.parse(raw.replace(/^\uFEFF/, ''));
if (data[field] !== undefined && data[field] !== null) console.log(String(data[field]));
JXA
}

json_array_contains() {
  local path="$1" value="$2"
  JSON_PATH="$path" JSON_VALUE="$value" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const path = $.getenv('JSON_PATH');
const value = $.getenv('JSON_VALUE');
  const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
  const data = JSON.parse(raw.replace(/^\uFEFF/, ''));
if (!Array.isArray(data) || !data.includes(value)) throw new Error('array value missing');
JXA
}

json_bool_field() {
  local path="$1" field="$2"
  [[ "$(json_field "$path" "$field")" == 'true' ]]
}

validate_note_root() {
  local value="$1"
  [[ -z "$value" || "$value" == '.' ]] && return 0
  [[ "$value" != /* && ! "$value" =~ (^|/)\.\.(/|$) ]] || return 1
  local old_ifs="$IFS" segment lower
  IFS='/' read -r -a segments <<< "$value"
  IFS="$old_ifs"
  for segment in "${segments[@]}"; do
    [[ -n "${segment//[[:space:]]/}" ]] || return 1
    [[ "$segment" != '.' && "$segment" != '..' && "$segment" != *'.' && "$segment" != *' ' && "$segment" != ' '* ]] || return 1
    [[ ! "$segment" =~ [[:cntrl:]] ]] || return 1
    [[ "$segment" != *'<'* && "$segment" != *'>'* && "$segment" != *':'* && "$segment" != *'"'* && "$segment" != *'|'* && "$segment" != *'?'* && "$segment" != *'*'* ]] || return 1
    lower="$(printf '%s' "$segment" | tr '[:upper:]' '[:lower:]')"
    [[ ! "$lower" =~ ^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$ ]] || return 1
    [[ "${#segment}" -le 120 ]] || return 1
  done
  [[ "${#value}" -le 240 ]]
}

mcp_section_exists() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  awk 'NR == 1 { sub(/^\357\273\277/, "") } /^[[:space:]]*\[mcp_servers\.obsidian\][[:space:]]*(#.*)?$/ { found=1 } END { exit(found ? 0 : 1) }' "$path"
}

mcp_value() {
  local path="$1" wanted="$2"
  awk -v wanted="$wanted" '
    NR == 1 { sub(/^\357\273\277/, "", $0) }
    /^[[:space:]]*\[/ { inside=($0 ~ /^[[:space:]]*\[mcp_servers\.obsidian\][[:space:]]*(#.*)?$/); next }
    inside { line=$0; sub(/[[:space:]]+#.*/, "", line); pattern="^[[:space:]]*" wanted "[[:space:]]*="; if (line ~ pattern) { sub(pattern, "", line); gsub(/^[[:space:]\"]+|[[:space:]\"]+$/, "", line); print line; exit } }
  ' "$path"
}

[[ -n "$VAULT_PATH" ]] || { echo 'Vault path is required.' >&2; exit 2; }
[[ -d "$VAULT_PATH" ]] || { echo "Vault directory does not exist: $VAULT_PATH" >&2; exit 2; }
VAULT_PATH="$(cd "$VAULT_PATH" && pwd -P)"
missing_commands=0
require_command() { if ! command -v "$1" >/dev/null 2>&1; then check "$1" 0 'Required command not found'; missing_commands=1; fi; }
require_command osascript
require_command curl
if [[ "$missing_commands" -eq 1 ]]; then
  echo
  echo "Doctor found $failures issue(s)."
  exit 1
fi
load_metadata
PLUGIN_ID="${PLUGIN_ID:-obsidian-local-rest-api}"
PLUGIN_VERSION="${PLUGIN_VERSION:-5.1.0}"

plugin_dir="$VAULT_PATH/.obsidian/plugins/$PLUGIN_ID"
manifest_path="$plugin_dir/manifest.json"
main_path="$plugin_dir/main.js"
data_path="$plugin_dir/data.json"
community_path="$VAULT_PATH/.obsidian/community-plugins.json"
settings_path="$VAULT_PATH/.codex-obsidian-knowledge.json"

plugin_files_ok=0
[[ -f "$main_path" && -f "$manifest_path" ]] && plugin_files_ok=1
check 'Plugin files' "$plugin_files_ok" "$plugin_dir"
manifest_ok=0
if [[ -f "$manifest_path" ]]; then
  if manifest_id="$(json_field "$manifest_path" id 2>/dev/null)" && manifest_version="$(json_field "$manifest_path" version 2>/dev/null)" && [[ "$manifest_id" == "$PLUGIN_ID" && "$manifest_version" == "$PLUGIN_VERSION" ]]; then manifest_ok=1; fi
fi
check 'Plugin identity/version' "$manifest_ok" "$PLUGIN_ID $PLUGIN_VERSION"

data_ok=0
api_key=''
if [[ -f "$data_path" ]]; then
  if api_key="$(json_field "$data_path" apiKey 2>/dev/null)" && [[ -n "$api_key" ]]; then data_ok=1; fi
fi
check 'Plugin API key' "$data_ok" 'value hidden'

enabled_ok=0
if [[ -f "$community_path" ]] && json_array_contains "$community_path" "$PLUGIN_ID" >/dev/null 2>&1; then enabled_ok=1; fi
check 'Plugin enabled' "$enabled_ok" "$community_path"

note_root=''
note_root_ok=1
if [[ -f "$settings_path" ]]; then
  if note_root="$(json_field "$settings_path" noteRoot 2>/dev/null)"; then :; else note_root_ok=0; fi
  validate_note_root "$note_root" || note_root_ok=0
fi
check 'Knowledge note root' "$note_root_ok" "${note_root:-Vault root}"

config_ok=0
endpoint=''
configured_env_name=''
configured_token=''
if [[ -f "$CODEX_CONFIG_PATH" ]] && mcp_section_exists "$CODEX_CONFIG_PATH"; then
  config_ok=1
  endpoint="$(mcp_value "$CODEX_CONFIG_PATH" url)"
  configured_env_name="$(mcp_value "$CODEX_CONFIG_PATH" bearer_token_env_var)"
fi
if [[ "$REPAIR" -eq 1 ]]; then
  [[ "$APPROVED" -eq 1 ]] || { echo 'Doctor repair changes plugin settings and the current-user credential. Re-run with --repair --approve after confirmation.' >&2; exit 1; }
  [[ -n "$api_key" && "$endpoint" =~ ^(https|http)://127\.0\.0\.1:([0-9]+)/mcp/$ ]] || { echo 'Cannot repair missing credentials or an unsupported endpoint.' >&2; exit 1; }
  [[ "$configured_env_name" == "$SECRET_ENV_NAME" ]] || { echo 'Cannot repair a Codex config that uses a different bearer_token_env_var.' >&2; exit 1; }
  repair_insecure=0
  [[ "${BASH_REMATCH[1]}" == 'http' ]] && repair_insecure=1
  repair_current="$(launchctl getenv "$SECRET_ENV_NAME" 2>/dev/null || true)"
  repair_process="${OBSIDIAN_LOCAL_REST_API_KEY-}"
  [[ -z "$repair_current" || "$repair_current" == "$api_key" ]] || { echo "$SECRET_ENV_NAME belongs to a different Vault; refusing to replace it." >&2; exit 1; }
  [[ -z "$repair_process" || "$repair_process" == "$api_key" ]] || { echo "$SECRET_ENV_NAME in the current process belongs to a different Vault; refusing to replace it." >&2; exit 1; }
  repair_data="$(mktemp "${TMPDIR:-/tmp}/codex-obsidian-doctor-data.XXXXXX")"
  REPAIR_SOURCE="$data_path" REPAIR_TARGET="$repair_data" REPAIR_INSECURE="$repair_insecure" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const source = $.getenv('REPAIR_SOURCE');
const target = $.getenv('REPAIR_TARGET');
const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(source, $.NSUTF8StringEncoding, null));
const data = JSON.parse(raw.replace(/^\uFEFF/, ''));
data.enableInsecureServer = $.getenv('REPAIR_INSECURE') === '1';
const text = JSON.stringify(data, null, 2) + '\n';
if (!$.NSString.stringWithString(text).writeToFileAtomicallyEncodingError(target, true, $.NSUTF8StringEncoding, null)) throw new Error('Could not stage data.json');
JXA
  mv -f -- "$repair_data" "$data_path"
  launchctl setenv "$SECRET_ENV_NAME" "$api_key"
  export "$SECRET_ENV_NAME=$api_key"
  zshenv="$HOME/.zshenv"; begin='# BEGIN codex-obsidian-knowledge'; end='# END codex-obsidian-knowledge'
  repair_clean="$(mktemp "${TMPDIR:-/tmp}/codex-obsidian-doctor-zshenv.XXXXXX")"
  if [[ -f "$zshenv" ]]; then awk -v begin="$begin" -v end="$end" '$0 == begin {skip=1; next} $0 == end {skip=0; next} !skip {print}' "$zshenv" > "$repair_clean"; fi
  printf '\n%s\nexport %s=%q\n%s\n' "$begin" "$SECRET_ENV_NAME" "$api_key" "$end" >> "$repair_clean"
  chmod 600 "$repair_clean"; mv -f -- "$repair_clean" "$zshenv"
  echo '[REPAIR] Reconciled the plugin protocol mode and current-user credential with Codex config (key hidden).'
fi
check 'Codex MCP section' "$config_ok" '[mcp_servers.obsidian]'
check 'Codex MCP endpoint' $([[ -n "$endpoint" ]] && echo 1 || echo 0) "${endpoint:-missing url entry}"
startup_timeout="$(mcp_value "$CODEX_CONFIG_PATH" startup_timeout_sec 2>/dev/null || true)"
tool_timeout="$(mcp_value "$CODEX_CONFIG_PATH" tool_timeout_sec 2>/dev/null || true)"
check 'MCP startup timeout' $([[ "$startup_timeout" == '20' ]] && echo 1 || echo 0) '20 seconds'
check 'MCP tool timeout' $([[ "$tool_timeout" == '60' ]] && echo 1 || echo 0) '60 seconds'
env_name_ok=0
[[ "$configured_env_name" == "$SECRET_ENV_NAME" ]] && env_name_ok=1
check 'Codex API key variable name' "$env_name_ok" "${configured_env_name:-missing bearer_token_env_var entry}"
if [[ "$env_name_ok" -eq 1 ]]; then
  configured_token="$(printenv "$configured_env_name" 2>/dev/null || true)"
  if [[ -z "$configured_token" ]] && command -v launchctl >/dev/null 2>&1; then configured_token="$(launchctl getenv "$configured_env_name" 2>/dev/null || true)"; fi
fi
check 'Codex API key variable' $([[ -n "$configured_token" ]] && echo 1 || echo 0) 'value hidden'
keys_match=0
[[ -n "$api_key" && -n "$configured_token" && "$api_key" == "$configured_token" ]] && keys_match=1
check 'API key match' "$keys_match" 'Plugin and Codex credential sources must agree (values hidden)'

endpoint_supported=0
endpoint_scheme=''
if [[ "$endpoint" =~ ^(https|http)://127\.0\.0\.1:([0-9]+)/mcp/$ ]]; then
  endpoint_scheme="${BASH_REMATCH[1]}"
  endpoint_port="${BASH_REMATCH[2]}"
  if [[ "$endpoint_port" -ge 1 && "$endpoint_port" -le 65535 ]]; then endpoint_supported=1; fi
fi
check 'Endpoint boundary' "$endpoint_supported" "${endpoint:-missing endpoint}"
http_intent_ok=1
if [[ "$endpoint_scheme" == 'http' && "$ALLOW_INSECURE_HTTP" -ne 1 ]]; then http_intent_ok=0; fi
http_intent_detail='HTTPS or explicit fallback'
[[ "$endpoint_scheme" == 'http' ]] && http_intent_detail='Requires --allow-insecure-http'
check 'HTTP fallback selection' "$http_intent_ok" "$http_intent_detail"
if [[ -n "$endpoint_scheme" && -f "$data_path" ]]; then
  protocol_mode_ok=0
  if [[ "$endpoint_scheme" == 'http' ]]; then
    json_bool_field "$data_path" enableInsecureServer && protocol_mode_ok=1
    protocol_mode_detail='HTTP endpoint requires enableInsecureServer=true'
  else
    if ! json_bool_field "$data_path" enableInsecureServer; then protocol_mode_ok=1; fi
    protocol_mode_detail='HTTPS endpoint requires enableInsecureServer=false'
  fi
  check 'Plugin protocol mode' "$protocol_mode_ok" "$protocol_mode_detail"
fi

mcp_json_response_name() {
  MCP_RESPONSE="$1" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const raw = $.getenv('MCP_RESPONSE');
  const line = raw.split(/\r?\n/).find((value) => value.trim().startsWith('data:'));
  const candidate = line ? line.replace(/^\s*data:\s*/, '') : raw.trim();
const data = JSON.parse(candidate);
if (data.error || !data.result || !data.result.serverInfo || !data.result.serverInfo.name) throw new Error('invalid initialize response');
console.log(String(data.result.serverInfo.name));
JXA
}

if [[ "$endpoint_supported" -eq 1 && "$http_intent_ok" -eq 1 && "$keys_match" -eq 1 ]]; then
  curl_args=(--fail --silent --show-error --max-time 5 -H "Authorization: Bearer $configured_token" -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"codex-obsidian-knowledge-doctor","version":"0.3.0"}}}')
  response=''
  if response="$(curl "${curl_args[@]}" "$endpoint" 2>/dev/null)" && server_name="$(mcp_json_response_name "$response" 2>/dev/null)"; then
    check 'MCP initialize' 1 "$server_name"
  elif [[ "$endpoint_scheme" == 'https' ]] && insecure_response="$(curl -k "${curl_args[@]}" "$endpoint" 2>/dev/null)" && mcp_json_response_name "$insecure_response" >/dev/null 2>&1; then
    check 'MCP initialize' 0 'Server responds only when TLS verification is disabled; trust the certificate or use the explicit HTTP fallback'
  else
    check 'MCP initialize' 0 'Request failed; check Obsidian, endpoint, API key, and plugin settings'
  fi
else
  check 'MCP initialize' 0 'Skipped because endpoint, credential, or HTTP intent is invalid'
fi

if [[ "$failures" -gt 0 ]]; then
  echo
  echo "Doctor found $failures issue(s)."
  exit 1
fi
echo
echo 'Doctor checks passed.'
