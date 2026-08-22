#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="obsidian-local-rest-api"
LOCAL_REST_API_VERSION="5.1.0"
PLUGIN_RELEASE_BASE="https://github.com/coddingtonbear/obsidian-local-rest-api/releases/download/${LOCAL_REST_API_VERSION}"
SECRET_ENV_NAME="OBSIDIAN_LOCAL_REST_API_KEY"
NOTE_ROOT="Codex知识库"
VAULT_PATH=""
CODEX_CONFIG_PATH="${HOME}/.codex/config.toml"
APPROVED=0
ALLOW_INSECURE_HTTP=0
NO_SECRET_IMPORT=0

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

die() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

normalize_note_root() {
  NOTE_ROOT="${NOTE_ROOT//\\//}"
  NOTE_ROOT="${NOTE_ROOT#/}"
  NOTE_ROOT="${NOTE_ROOT%/}"
  [[ "$NOTE_ROOT" != /* ]] || die "Note root must be relative to the Obsidian vault."
  [[ "$NOTE_ROOT" != *".."* ]] || die "Note root cannot contain .. segments."
}

discover_vaults() {
  local config_path="${HOME}/Library/Application Support/obsidian/obsidian.json"
  [[ -f "$config_path" ]] || return 0
  OBSIDIAN_CONFIG_PATH="$config_path" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const path = $.getenv('OBSIDIAN_CONFIG_PATH');
const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
const data = JSON.parse(raw);
for (const entry of Object.values(data.vaults || {})) {
  if (entry.path) console.log((entry.open ? '1' : '0') + '\t' + entry.path);
}
JXA
}

resolve_vault() {
  if [[ -n "$VAULT_PATH" ]]; then
    [[ -d "$VAULT_PATH" ]] || die "Vault directory does not exist: $VAULT_PATH"
    VAULT_PATH="$(cd "$VAULT_PATH" && pwd)"
    return
  fi

  local discovered=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && discovered+=("$line")
  done < <(discover_vaults || true)

  if [[ "${#discovered[@]}" -eq 1 ]]; then
    VAULT_PATH="${discovered[0]#*$'\t'}"
  elif [[ "${#discovered[@]}" -gt 1 ]]; then
    echo "Multiple Obsidian vaults were found:"
    local i=1
    for line in "${discovered[@]}"; do
      echo "[$i] ${line#*$'\t'}"
      ((i++))
    done
    read -r -p "Choose a vault number: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || die "Invalid vault selection."
    (( choice >= 1 && choice <= ${#discovered[@]} )) || die "Invalid vault selection."
    VAULT_PATH="${discovered[$((choice - 1))]#*$'\t'}"
  else
    read -r -p "Enter the absolute path of the Obsidian vault: " VAULT_PATH
  fi

  [[ -d "$VAULT_PATH" ]] || die "Vault directory does not exist: $VAULT_PATH"
  VAULT_PATH="$(cd "$VAULT_PATH" && pwd)"
}

confirm_bootstrap() {
  if [[ "$APPROVED" -eq 1 ]]; then return; fi
  read -r -p "This will download '$PLUGIN_ID', modify the selected Obsidian vault, and update Codex MCP configuration. Continue? (y/N) " answer
  [[ "$answer" =~ ^[Yy]$|^是$|^确认$ ]] || die "Bootstrap cancelled by user."
}

write_json_with_jxa() {
  local target="$1"
  local mode="$2"
  TARGET_PATH="$target" MODE="$mode" PLUGIN_ID="$PLUGIN_ID" NEW_API_KEY="${NEW_API_KEY:-}" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const path = $.getenv('TARGET_PATH');
const mode = $.getenv('MODE');
const pluginId = $.getenv('PLUGIN_ID');
const newApiKey = $.getenv('NEW_API_KEY');
let data = {};
const file = $.NSFileManager.defaultManager;
if (file.fileExistsAtPath(path)) {
  const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
  if (raw.trim()) data = JSON.parse(raw);
}
if (mode === 'data') {
  if (!data.apiKey) data.apiKey = newApiKey;
} else if (mode === 'plugins') {
  if (!Array.isArray(data)) data = [];
  if (!data.includes(pluginId)) data.push(pluginId);
} else if (mode === 'app') {
  if (typeof data !== 'object' || Array.isArray(data)) data = {};
  data.communityPlugins = true;
}
const text = JSON.stringify(data, null, 2) + '\n';
$.NSString.stringWithString(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
JXA
}

install_plugin() {
  local obsidian_dir="$VAULT_PATH/.obsidian"
  local plugin_dir="$obsidian_dir/plugins/$PLUGIN_ID"
  mkdir -p "$plugin_dir"
  local temporary_dir
  temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-obsidian.XXXXXX")"
  trap 'rm -rf "$temporary_dir"' RETURN

  for file_name in main.js manifest.json styles.css; do
    echo "Downloading Local REST API $file_name..."
    curl --fail --location --silent --show-error --retry 3 \
      "$PLUGIN_RELEASE_BASE/$file_name" \
      --output "$temporary_dir/$file_name"
    mv -f "$temporary_dir/$file_name" "$plugin_dir/$file_name"
  done

  local data_path="$plugin_dir/data.json"
  local api_key=""
  if [[ -f "$data_path" ]]; then
    api_key="$(grep -o '"apiKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$data_path" | head -n 1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/' || true)"
  fi
  if [[ -z "$api_key" ]]; then
    api_key="$(openssl rand -hex 32 2>/dev/null || uuidgen | tr -d '-')"
    NEW_API_KEY="$api_key" write_json_with_jxa "$data_path" data
  fi
  API_KEY="$api_key"

  mkdir -p "$obsidian_dir"
  write_json_with_jxa "$obsidian_dir/community-plugins.json" plugins
  write_json_with_jxa "$obsidian_dir/app.json" app
}

set_secret_environment() {
  [[ "$NO_SECRET_IMPORT" -eq 1 ]] && { echo "Skipped secret import because --no-secret-import was supplied."; return; }
  export "$SECRET_ENV_NAME=$API_KEY"
  if command -v launchctl >/dev/null 2>&1; then
    launchctl setenv "$SECRET_ENV_NAME" "$API_KEY"
  fi

  local zshenv="${HOME}/.zshenv"
  local begin="# BEGIN codex-obsidian-knowledge"
  local end="# END codex-obsidian-knowledge"
  local temporary
  temporary="$(mktemp "${TMPDIR:-/tmp}/codex-zshenv.XXXXXX")"
  if [[ -f "$zshenv" ]]; then
    awk -v begin="$begin" -v end="$end" '$0 == begin {skip=1; next} $0 == end {skip=0; next} !skip {print}' "$zshenv" > "$temporary"
  fi
  {
    cat "$temporary" 2>/dev/null || true
    printf '\n%s\nexport %s=%q\n%s\n' "$begin" "$SECRET_ENV_NAME" "$API_KEY" "$end"
  } > "$zshenv"
  rm -f "$temporary"
  echo "Configured $SECRET_ENV_NAME for macOS GUI processes and future zsh sessions."
}

set_codex_mcp() {
  local endpoint="https://127.0.0.1:27124/mcp/"
  if [[ "$ALLOW_INSECURE_HTTP" -eq 1 ]]; then
    endpoint="http://127.0.0.1:27123/mcp/"
  fi
  mkdir -p "$(dirname "$CODEX_CONFIG_PATH")"
  touch "$CODEX_CONFIG_PATH"
  if grep -q '^\[mcp_servers\.obsidian\]$' "$CODEX_CONFIG_PATH"; then
    local section
    section="$(awk '/^\[mcp_servers\.obsidian\]$/{inside=1; next} /^\[/{inside=0} inside{print}' "$CODEX_CONFIG_PATH")"
    echo "$section" | grep -Fqx "url = \"$endpoint\"" || die "Existing [mcp_servers.obsidian] section differs from requested endpoint: $CODEX_CONFIG_PATH"
    echo "$section" | grep -Fqx "bearer_token_env_var = \"$SECRET_ENV_NAME\"" || die "Existing [mcp_servers.obsidian] auth differs from requested environment variable: $CODEX_CONFIG_PATH"
  else
    {
      [[ ! -s "$CODEX_CONFIG_PATH" ]] || printf '\n'
      printf '[mcp_servers.obsidian]\nurl = "%s"\nbearer_token_env_var = "%s"\nstartup_timeout_sec = 20\ntool_timeout_sec = 60\n' "$endpoint" "$SECRET_ENV_NAME"
    } >> "$CODEX_CONFIG_PATH"
  fi
  MCP_ENDPOINT="$endpoint"
}

require_command curl
require_command osascript
require_command openssl
normalize_note_root
resolve_vault
confirm_bootstrap
install_plugin
printf '{"version":1,"noteRoot":%s}\n' "$(printf '%s' "$NOTE_ROOT" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed 's/^/"/; s/$/"/')" > "$VAULT_PATH/.codex-obsidian-knowledge.json"
set_secret_environment
set_codex_mcp

echo
echo "Local REST API was installed and enabled for vault: $VAULT_PATH"
echo "MCP endpoint: $MCP_ENDPOINT"
echo 'Restart Obsidian once so it loads the downloaded plugin, then restart Codex.'
echo 'Run scripts/doctor.sh to verify the connection.'
