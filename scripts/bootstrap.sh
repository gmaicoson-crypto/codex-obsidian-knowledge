#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
METADATA_PATH="$SCRIPT_DIR/upstream-assets.json"
SECRET_ENV_NAME="OBSIDIAN_LOCAL_REST_API_KEY"
NOTE_ROOT="Codex知识库"
VAULT_PATH=""
CODEX_CONFIG_PATH="${CODEX_HOME:-$HOME/.codex}/config.toml"
APPROVED=0
ALLOW_INSECURE_HTTP=0
NO_SECRET_IMPORT=0
INSTALL_TEMPORARY_DIR=""
ZSHENV_TEMPORARY=""
ZSHENV_SOURCE_TEMPORARY=""

cleanup_temporary_files() {
  [[ -z "$INSTALL_TEMPORARY_DIR" ]] || rm -rf -- "$INSTALL_TEMPORARY_DIR"
  [[ -z "$ZSHENV_TEMPORARY" ]] || rm -f -- "$ZSHENV_TEMPORARY"
  [[ -z "$ZSHENV_SOURCE_TEMPORARY" ]] || rm -f -- "$ZSHENV_SOURCE_TEMPORARY"
}
trap cleanup_temporary_files EXIT

usage() {
  cat <<'EOF'
Usage: ./scripts/bootstrap.sh [options]

Options:
  --vault PATH              Absolute path to an Obsidian vault.
  --note-root PATH          Relative note root inside the vault.
  --codex-config PATH       Codex config path override.
  --approve                 Confirm installation and configuration changes.
  --allow-insecure-http     Use http://127.0.0.1:27123/mcp/ fallback.
  --no-secret-import        Do not persist the API key into the user environment.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault) VAULT_PATH="${2:?Missing value for --vault}"; shift 2 ;;
    --note-root) NOTE_ROOT="${2:?Missing value for --note-root}"; shift 2 ;;
    --codex-config) CODEX_CONFIG_PATH="${2:?Missing value for --codex-config}"; shift 2 ;;
    --approve) APPROVED=1; shift ;;
    --allow-insecure-http) ALLOW_INSECURE_HTTP=1; shift ;;
    --no-secret-import) NO_SECRET_IMPORT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

die() { echo "Error: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

load_metadata() {
  [[ -f "$METADATA_PATH" ]] || die "Upstream asset metadata is missing: $METADATA_PATH"
  local lines
  lines="$(METADATA_PATH="$METADATA_PATH" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const path = $.getenv('METADATA_PATH');
const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
const data = JSON.parse(raw.replace(/^\uFEFF/, ''));
console.log(data.pluginId);
console.log(data.version);
console.log(data.releaseBase);
for (const name of ['main.js', 'manifest.json', 'styles.css']) console.log(name + '\t' + data.assets[name]);
JXA
)" || die "Could not parse upstream asset metadata."
  PLUGIN_ID="$(printf '%s\n' "$lines" | sed -n '1p')"
  LOCAL_REST_API_VERSION="$(printf '%s\n' "$lines" | sed -n '2p')"
  PLUGIN_RELEASE_BASE="$(printf '%s\n' "$lines" | sed -n '3p')"
  [[ -n "$PLUGIN_ID" && -n "$LOCAL_REST_API_VERSION" && -n "$PLUGIN_RELEASE_BASE" ]] || die 'Upstream asset metadata is incomplete.'
  ASSET_METADATA_LINES="$(printf '%s\n' "$lines" | tail -n +4)"
}

asset_hash() {
  local file_name="$1"
  printf '%s\n' "$ASSET_METADATA_LINES" | awk -F '\t' -v wanted="$file_name" '$1 == wanted { print $2; exit }'
}

normalize_note_root() {
  NOTE_ROOT="${NOTE_ROOT//\\\\//}"
  [[ -z "$NOTE_ROOT" || "$NOTE_ROOT" == "." ]] && { NOTE_ROOT=""; return; }
  [[ "$NOTE_ROOT" != /* ]] || die 'Note root must be relative to the Obsidian vault.'
  NOTE_ROOT="${NOTE_ROOT%/}"
  [[ "$NOTE_ROOT" != *$'\n'* && "$NOTE_ROOT" != *$'\r'* ]] || die 'Note root cannot contain control characters.'
  [[ ! "$NOTE_ROOT" =~ (^|/)\.\.(/|$) ]] || die 'Note root cannot contain .. segments.'
  local old_ifs="$IFS" segment lower
  IFS='/' read -r -a note_segments <<< "$NOTE_ROOT"
  IFS="$old_ifs"
  for segment in "${note_segments[@]}"; do
    [[ -n "${segment//[[:space:]]/}" ]] || die 'Note root contains an empty segment.'
    [[ "$segment" != '.' && "$segment" != '..' && "$segment" != *'.' && "$segment" != *' ' && "$segment" != ' '* ]] || die "Invalid note-root segment: $segment"
    [[ ! "$segment" =~ [[:cntrl:]] ]] || die "Invalid note-root segment: $segment"
    [[ "$segment" != *'<'* && "$segment" != *'>'* && "$segment" != *':'* && "$segment" != *'"'* && "$segment" != *'|'* && "$segment" != *'?'* && "$segment" != *'*'* ]] || die "Invalid note-root segment: $segment"
    lower="$(printf '%s' "$segment" | tr '[:upper:]' '[:lower:]')"
    [[ ! "$lower" =~ ^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$ ]] || die "Reserved Windows filename in note root: $segment"
    [[ "${#segment}" -le 120 ]] || die 'Each note-root segment must be 120 characters or fewer.'
  done
  [[ "${#NOTE_ROOT}" -le 240 ]] || die 'Note root must be 240 characters or fewer.'
}

discover_vaults() {
  local config_path="${HOME}/Library/Application Support/obsidian/obsidian.json"
  [[ -f "$config_path" ]] || return 0
  OBSIDIAN_CONFIG_PATH="$config_path" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const path = $.getenv('OBSIDIAN_CONFIG_PATH');
const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
const data = JSON.parse(raw.replace(/^\uFEFF/, ''));
for (const entry of Object.values(data.vaults || {})) if (entry.path) console.log((entry.open ? '1' : '0') + '\t' + entry.path);
JXA
}

resolve_vault() {
  if [[ -n "$VAULT_PATH" ]]; then
    [[ -d "$VAULT_PATH" ]] || die "Vault directory does not exist: $VAULT_PATH"
    VAULT_PATH="$(cd "$VAULT_PATH" && pwd -P)"
    return
  fi
  local discovered=() line choice i=1
  while IFS= read -r line; do [[ -n "$line" ]] && discovered+=("$line"); done < <(discover_vaults || true)
  if [[ "${#discovered[@]}" -eq 1 ]]; then
    VAULT_PATH="${discovered[0]#*$'\t'}"
  elif [[ "${#discovered[@]}" -gt 1 ]]; then
    echo 'Multiple Obsidian vaults were found:'
    for line in "${discovered[@]}"; do echo "[$i] ${line#*$'\t'}"; i=$((i + 1)); done
    read -r -p 'Choose a vault number: ' choice
    [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#discovered[@]}" ]] || die 'Invalid vault selection.'
    VAULT_PATH="${discovered[$((choice - 1))]#*$'\t'}"
  else
    read -r -p 'Enter the absolute path of the Obsidian vault: ' VAULT_PATH
  fi
  [[ -d "$VAULT_PATH" ]] || die "Vault directory does not exist: $VAULT_PATH"
  VAULT_PATH="$(cd "$VAULT_PATH" && pwd -P)"
}

confirm_bootstrap() {
  if [[ "$APPROVED" -eq 1 ]]; then return; fi
  read -r -p "This will download '$PLUGIN_ID', modify the selected Obsidian vault, and update Codex MCP configuration. Continue? (y/N) " answer
  [[ "$answer" =~ ^[Yy]$|^是$|^确认$ ]] || die 'Bootstrap cancelled by user.'
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

write_json_with_jxa() {
  local target="$1" mode="$2"
  TARGET_PATH="$target" MODE="$mode" PLUGIN_ID="$PLUGIN_ID" NEW_API_KEY="${NEW_API_KEY:-}" NOTE_ROOT="$NOTE_ROOT" ENABLE_INSECURE_SERVER="$ALLOW_INSECURE_HTTP" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const path = $.getenv('TARGET_PATH');
const mode = $.getenv('MODE');
const pluginId = $.getenv('PLUGIN_ID');
const newApiKey = $.getenv('NEW_API_KEY');
const noteRoot = $.getenv('NOTE_ROOT');
const enableInsecureServer = $.getenv('ENABLE_INSECURE_SERVER') === '1';
const file = $.NSFileManager.defaultManager;
const exists = file.fileExistsAtPath(path);
let data = {};
if (exists) {
  const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
  if (!raw.trim()) throw new Error('JSON settings file is empty');
  data = JSON.parse(raw.replace(/^\uFEFF/, ''));
}
if (mode === 'data') {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) throw new Error('data.json must contain an object');
  if (!data.apiKey) data.apiKey = newApiKey;
  if (enableInsecureServer) data.enableInsecureServer = true;
} else if (mode === 'plugins') {
  if (!exists) data = [];
  else if (!Array.isArray(data)) throw new Error('community-plugins.json must contain an array');
  if (!data.includes(pluginId)) data.push(pluginId);
} else if (mode === 'app') {
  if (!exists) data = {};
  else if (typeof data !== 'object' || data === null || Array.isArray(data)) throw new Error('app.json must contain an object');
  data.communityPlugins = true;
} else if (mode === 'settings') {
  data = { version: 1, noteRoot: noteRoot };
}
const text = JSON.stringify(data, null, 2) + '\n';
if (!$.NSString.stringWithString(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null)) throw new Error('Could not write JSON file');
JXA
}

validate_manifest() {
  MANIFEST_PATH="$1" EXPECTED_ID="$PLUGIN_ID" EXPECTED_VERSION="$LOCAL_REST_API_VERSION" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const path = $.getenv('MANIFEST_PATH');
const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
const data = JSON.parse(raw.replace(/^\uFEFF/, ''));
if (data.id !== $.getenv('EXPECTED_ID') || data.version !== $.getenv('EXPECTED_VERSION')) throw new Error('manifest does not match pinned plugin');
JXA
}

verify_asset() {
  local path="$1" file_name="$2" expected actual
  expected="$(asset_hash "$file_name")"
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || die "No valid SHA-256 is pinned for upstream asset: $file_name"
  actual="$(shasum -a 256 "$path" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "SHA-256 verification failed for upstream asset: $file_name"
}

mcp_section_exists() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  awk '
    NR == 1 { sub(/^\357\273\277/, "") }
    /^[[:space:]]*\[mcp_servers\.obsidian\][[:space:]]*(#.*)?$/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$path"
}

mcp_value() {
  local path="$1" wanted="$2"
  awk -v wanted="$wanted" '
    NR == 1 { sub(/^\357\273\277/, "", $0) }
    /^[[:space:]]*\[/ { inside=($0 ~ /^[[:space:]]*\[mcp_servers\.obsidian\][[:space:]]*(#.*)?$/); next }
    inside {
      line=$0; sub(/[[:space:]]+#.*/, "", line)
      pattern="^[[:space:]]*" wanted "[[:space:]]*="
      if (line ~ pattern) {
        sub(pattern, "", line); gsub(/^[[:space:]\"]+|[[:space:]\"]+$/, "", line); print line; exit
      }
    }
  ' "$path"
}

assert_mcp_config_compatible() {
  local endpoint="$1"
  if ! mcp_section_exists "$CODEX_CONFIG_PATH"; then return; fi
  [[ "$(mcp_value "$CODEX_CONFIG_PATH" url)" == "$endpoint" ]] || die "Existing [mcp_servers.obsidian] section differs from requested endpoint: $CODEX_CONFIG_PATH"
  [[ "$(mcp_value "$CODEX_CONFIG_PATH" bearer_token_env_var)" == "$SECRET_ENV_NAME" ]] || die "Existing [mcp_servers.obsidian] auth differs from requested environment variable: $CODEX_CONFIG_PATH"
  [[ "$(mcp_value "$CODEX_CONFIG_PATH" startup_timeout_sec)" == '20' ]] || die "Existing [mcp_servers.obsidian] startup timeout differs: $CODEX_CONFIG_PATH"
  [[ "$(mcp_value "$CODEX_CONFIG_PATH" tool_timeout_sec)" == '60' ]] || die "Existing [mcp_servers.obsidian] tool timeout differs: $CODEX_CONFIG_PATH"
}

build_config_stage() {
  local stage_path="$1" endpoint="$2"
  mkdir -p "$(dirname "$stage_path")"
  if [[ -f "$CODEX_CONFIG_PATH" ]]; then
    cp "$CODEX_CONFIG_PATH" "$stage_path"
  else
    : > "$stage_path"
  fi
  if ! mcp_section_exists "$stage_path"; then
    if [[ -s "$stage_path" ]]; then printf '\n' >> "$stage_path"; fi
    printf '[mcp_servers.obsidian]\nurl = "%s"\nbearer_token_env_var = "%s"\nstartup_timeout_sec = 20\ntool_timeout_sec = 60\n' "$endpoint" "$SECRET_ENV_NAME" >> "$stage_path"
  fi
}

install_plugin() {
  local endpoint="$1"
  local obsidian_dir="$VAULT_PATH/.obsidian"
  local plugin_dir="$obsidian_dir/plugins/$PLUGIN_ID"
  local community_path="$obsidian_dir/community-plugins.json"
  local app_path="$obsidian_dir/app.json"
  local settings_path="$VAULT_PATH/.codex-obsidian-knowledge.json"
  local temporary_dir staging_plugin_dir backup_dir
  temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-obsidian.XXXXXX")"
  INSTALL_TEMPORARY_DIR="$temporary_dir"
  staging_plugin_dir="$temporary_dir/plugin/$PLUGIN_ID"
  backup_dir="$temporary_dir/backup"
  mkdir -p "$staging_plugin_dir" "$backup_dir"
  if [[ -d "$plugin_dir" ]]; then cp -R "$plugin_dir/." "$staging_plugin_dir/"; fi

  local file_name download_path
  for file_name in main.js manifest.json styles.css; do
    echo "Downloading and verifying Local REST API $file_name..."
    download_path="$staging_plugin_dir/$file_name"
    curl --fail --location --silent --show-error --retry 3 "$PLUGIN_RELEASE_BASE/$file_name" --output "$download_path"
    verify_asset "$download_path" "$file_name"
  done
  validate_manifest "$staging_plugin_dir/manifest.json" || die 'Downloaded plugin manifest validation failed.'

  local data_path="$staging_plugin_dir/data.json" api_key
  if [[ -f "$data_path" ]]; then api_key="$(json_field "$data_path" apiKey)"; else api_key=""; fi
  [[ -n "$api_key" ]] || api_key="$(openssl rand -hex 32)"
  NEW_API_KEY="$api_key" write_json_with_jxa "$data_path" data

  local staging_community="$temporary_dir/community-plugins.json"
  local staging_app="$temporary_dir/app.json"
  local staging_settings="$temporary_dir/.codex-obsidian-knowledge.json"
  local staging_config="$temporary_dir/config.toml"
  if [[ -f "$community_path" ]]; then cp "$community_path" "$staging_community"; fi
  write_json_with_jxa "$staging_community" plugins
  if [[ -f "$app_path" ]]; then cp "$app_path" "$staging_app"; fi
  write_json_with_jxa "$staging_app" app
  write_json_with_jxa "$staging_settings" settings
  build_config_stage "$staging_config" "$endpoint"

  local sources=("$staging_plugin_dir" "$staging_community" "$staging_app" "$staging_settings" "$staging_config")
  local targets=("$plugin_dir" "$community_path" "$app_path" "$settings_path" "$CODEX_CONFIG_PATH")
  local backups=() committed=() backup_exists=() i target source backup commit_ok=1
  for i in "${!targets[@]}"; do
    target="${targets[$i]}"; source="${sources[$i]}"
    if [[ -e "$target" ]]; then
      backup="$backup_dir/item-$i"
      if ! mv "$target" "$backup"; then commit_ok=0; break; fi
      backups[$i]="$backup"; backup_exists[$i]=1
    else
      backup_exists[$i]=0
    fi
    mkdir -p "$(dirname "$target")"
    if ! mv "$source" "$target"; then commit_ok=0; break; fi
    committed[$i]="$target"
  done
  if [[ "$commit_ok" -ne 1 ]]; then
    for ((i=${#targets[@]}-1; i>=0; i--)); do
      [[ -n "${committed[$i]:-}" && -e "${committed[$i]}" ]] && rm -rf -- "${committed[$i]}"
      if [[ "${backup_exists[$i]:-0}" -eq 1 && -e "${backups[$i]}" ]]; then
        mkdir -p "$(dirname "${targets[$i]}")"
        mv "${backups[$i]}" "${targets[$i]}"
      fi
    done
    rm -rf -- "$temporary_dir"
    die 'Bootstrap failed while committing files; original files were restored.'
  fi
  API_KEY="$api_key"
  rm -rf -- "$temporary_dir"
  INSTALL_TEMPORARY_DIR=""
}

set_secret_environment() {
  if [[ "$NO_SECRET_IMPORT" -eq 1 ]]; then echo "Skipped secret import because --no-secret-import was supplied."; return; fi
  export "$SECRET_ENV_NAME=$API_KEY"
  if command -v launchctl >/dev/null 2>&1; then launchctl setenv "$SECRET_ENV_NAME" "$API_KEY"; fi
  local zshenv="${HOME}/.zshenv" begin='# BEGIN codex-obsidian-knowledge' end='# END codex-obsidian-knowledge'
  ZSHENV_SOURCE_TEMPORARY="$(mktemp "${zshenv}.XXXXXX")"
  ZSHENV_TEMPORARY="$(mktemp "${zshenv}.XXXXXX")"
  if [[ -f "$zshenv" ]]; then awk -v begin="$begin" -v end="$end" '$0 == begin {skip=1; next} $0 == end {skip=0; next} !skip {print}' "$zshenv" > "$ZSHENV_SOURCE_TEMPORARY"; fi
  { cat "$ZSHENV_SOURCE_TEMPORARY" 2>/dev/null || true; printf '\n%s\nexport %s=%q\n%s\n' "$begin" "$SECRET_ENV_NAME" "$API_KEY" "$end"; } > "$ZSHENV_TEMPORARY"
  rm -f -- "$ZSHENV_SOURCE_TEMPORARY"
  ZSHENV_SOURCE_TEMPORARY=""
  chmod 600 "$ZSHENV_TEMPORARY" 2>/dev/null || true
  mv -f -- "$ZSHENV_TEMPORARY" "$zshenv"
  ZSHENV_TEMPORARY=""
  echo "Configured $SECRET_ENV_NAME for macOS GUI processes and future zsh sessions."
}

require_command curl
require_command osascript
require_command openssl
require_command shasum
load_metadata
normalize_note_root
resolve_vault
endpoint='https://127.0.0.1:27124/mcp/'
if [[ "$ALLOW_INSECURE_HTTP" -eq 1 ]]; then endpoint='http://127.0.0.1:27123/mcp/'; fi
assert_mcp_config_compatible "$endpoint"
confirm_bootstrap
install_plugin "$endpoint"
set_secret_environment

echo
echo "Local REST API was installed and enabled for vault: $VAULT_PATH"
echo "MCP endpoint: $endpoint"
echo 'Restart Obsidian once so it loads the downloaded plugin, then restart Codex.'
echo 'Run scripts/doctor.sh to verify the connection.'
