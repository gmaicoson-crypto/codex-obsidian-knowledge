#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ACTION=""
VAULT_PATH=""
CODEX_CONFIG_PATH="${CODEX_HOME:-$HOME/.codex}/config.toml"
APPROVED=0
NO_SECRET_IMPORT=0
SECRET_ENV_NAME='OBSIDIAN_LOCAL_REST_API_KEY'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action) ACTION="${2:?Missing value for --action}"; shift 2 ;;
    --vault) VAULT_PATH="${2:?Missing value for --vault}"; shift 2 ;;
    --codex-config) CODEX_CONFIG_PATH="${2:?Missing value for --codex-config}"; shift 2 ;;
    --approve) APPROVED=1; shift ;;
    --no-secret-import) NO_SECRET_IMPORT=1; shift ;;
    -h|--help) echo 'Usage: connection-maintenance.sh --action rotate-key|disconnect|uninstall --vault /absolute/vault [--codex-config path] [--no-secret-import] --approve'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ "$ACTION" =~ ^(rotate-key|disconnect|uninstall)$ ]] || { echo 'A valid --action is required.' >&2; exit 2; }
[[ "$APPROVED" -eq 1 ]] || { echo "$ACTION changes the selected Vault and current-user Codex connection. Re-run with --approve after confirmation." >&2; exit 1; }
[[ "$(uname -s)" == 'Darwin' ]] || { echo 'This script supports macOS only. Use connection-maintenance.ps1 on Windows.' >&2; exit 1; }
[[ -d "$VAULT_PATH" ]] || { echo "Vault directory does not exist: $VAULT_PATH" >&2; exit 2; }
VAULT_PATH="$(cd "$VAULT_PATH" && pwd -P)"

for command_name in osascript openssl awk; do
  command -v "$command_name" >/dev/null 2>&1 || { echo "Required command not found: $command_name" >&2; exit 1; }
done

PLUGIN_ID="$(METADATA_PATH="$SCRIPT_DIR/upstream-assets.json" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const path = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('METADATA_PATH'));
const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
String(JSON.parse(raw.replace(/^\uFEFF/, '')).pluginId);
JXA
)"
PLUGIN_DIR="$VAULT_PATH/.obsidian/plugins/$PLUGIN_ID"
DATA_PATH="$PLUGIN_DIR/data.json"
COMMUNITY_PATH="$VAULT_PATH/.obsidian/community-plugins.json"
SETTINGS_PATH="$VAULT_PATH/.codex-obsidian-knowledge.json"
[[ "$PLUGIN_DIR" == "$VAULT_PATH/"* ]] || { echo 'Resolved plugin directory escaped the selected Vault.' >&2; exit 1; }

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-obsidian-maintenance.XXXXXX")"
COMMIT_SUCCESS=0
declare -a TARGETS=() BACKUPS=() CREATED=()

rollback() {
  local status=$?
  if [[ "$COMMIT_SUCCESS" -ne 1 ]]; then
    local i
    for ((i=${#TARGETS[@]}-1; i>=0; i--)); do
      if [[ "${CREATED[$i]:-0}" -eq 1 && -e "${TARGETS[$i]}" ]]; then rm -rf -- "${TARGETS[$i]}"; fi
      if [[ -n "${BACKUPS[$i]:-}" && -e "${BACKUPS[$i]}" ]]; then
        mkdir -p "$(dirname "${TARGETS[$i]}")"
        mv "${BACKUPS[$i]}" "${TARGETS[$i]}"
      fi
    done
  fi
  rm -rf -- "$WORK_DIR"
  exit "$status"
}
trap rollback EXIT

json_field() {
  JSON_PATH="$1" JSON_FIELD="$2" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const path = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('JSON_PATH'));
const field = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('JSON_FIELD'));
const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
const data = JSON.parse(raw.replace(/^\uFEFF/, ''));
data[field] !== undefined && data[field] !== null ? String(data[field]) : '';
JXA
}

stage_data() {
  local source="$1" target="$2" key="$3" insecure="$4"
  DATA_SOURCE="$source" DATA_TARGET="$target" NEW_KEY="$key" INSECURE="$insecure" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const source = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('DATA_SOURCE'));
const target = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('DATA_TARGET'));
const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(source, $.NSUTF8StringEncoding, null));
const data = JSON.parse(raw.replace(/^\uFEFF/, ''));
if (typeof data !== 'object' || data === null || Array.isArray(data)) throw new Error('data.json must contain an object');
const key = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('NEW_KEY'));
if (key) data.apiKey = key;
data.enableInsecureServer = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('INSECURE')) === '1';
const text = JSON.stringify(data, null, 2) + '\n';
if (!$.NSString.stringWithString(text).writeToFileAtomicallyEncodingError(target, true, $.NSUTF8StringEncoding, null)) throw new Error('Could not stage data.json');
JXA
}

stage_community_without_plugin() {
  local source="$1" target="$2"
  COMMUNITY_SOURCE="$source" COMMUNITY_TARGET="$target" PLUGIN_ID="$PLUGIN_ID" osascript -l JavaScript <<'JXA'
ObjC.import('Foundation');
const source = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('COMMUNITY_SOURCE'));
const target = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('COMMUNITY_TARGET'));
const raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(source, $.NSUTF8StringEncoding, null));
const data = JSON.parse(raw.replace(/^\uFEFF/, ''));
if (!Array.isArray(data)) throw new Error('community-plugins.json must contain an array');
const pluginId = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('PLUGIN_ID'));
const filtered = data.filter((value) => String(value) !== pluginId);
const text = JSON.stringify(filtered, null, 2) + '\n';
if (!$.NSString.stringWithString(text).writeToFileAtomicallyEncodingError(target, true, $.NSUTF8StringEncoding, null)) throw new Error('Could not stage community-plugins.json');
JXA
}

stage_config_without_mcp() {
  local source="$1" target="$2"
  awk '
    NR == 1 { sub(/^\357\273\277/, "") }
    /^[[:space:]]*\[/ {
      if ($0 ~ /^[[:space:]]*\[mcp_servers\.obsidian\][[:space:]]*(#.*)?$/) { skip=1; next }
      skip=0
    }
    !skip { print }
  ' "$source" > "$target"
}

commit_replace() {
  local source="$1" target="$2" index backup=""
  index="${#TARGETS[@]}"
  if [[ -e "$target" ]]; then backup="$WORK_DIR/backup-$index"; mv "$target" "$backup"; fi
  TARGETS[$index]="$target"; BACKUPS[$index]="$backup"; CREATED[$index]=0
  mkdir -p "$(dirname "$target")"
  mv "$source" "$target"
  CREATED[$index]=1
}

commit_delete() {
  local target="$1" index backup
  [[ -e "$target" ]] || return 0
  index="${#TARGETS[@]}"; backup="$WORK_DIR/backup-$index"
  mv "$target" "$backup"
  TARGETS[$index]="$target"; BACKUPS[$index]="$backup"; CREATED[$index]=0
}

update_zshenv() {
  local mode="$1" key="${2:-}" zshenv="$HOME/.zshenv" begin='# BEGIN codex-obsidian-knowledge' end='# END codex-obsidian-knowledge'
  local clean="$WORK_DIR/zshenv-clean" staged="$WORK_DIR/zshenv-staged"
  if [[ -f "$zshenv" ]]; then awk -v begin="$begin" -v end="$end" '$0 == begin {skip=1; next} $0 == end {skip=0; next} !skip {print}' "$zshenv" > "$clean"; else : > "$clean"; fi
  cp "$clean" "$staged"
  if [[ "$mode" == 'set' ]]; then printf '\n%s\nexport %s=%q\n%s\n' "$begin" "$SECRET_ENV_NAME" "$key" "$end" >> "$staged"; fi
  chmod 600 "$staged"
  commit_replace "$staged" "$zshenv"
}

read_managed_zsh_key() {
  local zshenv="$HOME/.zshenv" begin='# BEGIN codex-obsidian-knowledge' end='# END codex-obsidian-knowledge'
  [[ -f "$zshenv" ]] || return 0
  awk -v begin="$begin" -v end="$end" -v variable="$SECRET_ENV_NAME" '
    $0 == begin {inside=1; next}
    $0 == end {inside=0; next}
    inside && index($0, "export " variable "=") == 1 {
      sub("^export " variable "=", "")
      print
      exit
    }
  ' "$zshenv"
}

OLD_KEY=""
if [[ -f "$DATA_PATH" ]]; then OLD_KEY="$(json_field "$DATA_PATH" apiKey)"; fi

if [[ "$ACTION" == 'rotate-key' ]]; then
  [[ -n "$OLD_KEY" ]] || { echo 'The selected Vault has no Local REST API key to rotate.' >&2; exit 1; }
  CURRENT_KEY="$(launchctl getenv "$SECRET_ENV_NAME" 2>/dev/null || true)"
  MANAGED_ZSH_KEY="$(read_managed_zsh_key)"
  if [[ "$NO_SECRET_IMPORT" -ne 1 ]]; then
    [[ -z "$CURRENT_KEY" || "$CURRENT_KEY" == "$OLD_KEY" ]] || { echo "$SECRET_ENV_NAME does not match this Vault; refusing to replace it." >&2; exit 1; }
    [[ -z "$MANAGED_ZSH_KEY" || "$MANAGED_ZSH_KEY" == "$OLD_KEY" ]] || { echo "$SECRET_ENV_NAME in the managed .zshenv block does not match this Vault; refusing to replace it." >&2; exit 1; }
  fi
  NEW_KEY="$(openssl rand -hex 32)"
  STAGED_DATA="$WORK_DIR/data.json"
  stage_data "$DATA_PATH" "$STAGED_DATA" "$NEW_KEY" 0
  commit_replace "$STAGED_DATA" "$DATA_PATH"
  if [[ "$NO_SECRET_IMPORT" -ne 1 ]]; then
    update_zshenv set "$NEW_KEY"
    launchctl setenv "$SECRET_ENV_NAME" "$NEW_KEY"
    export "$SECRET_ENV_NAME=$NEW_KEY"
  fi
  COMMIT_SUCCESS=1
  echo 'Rotated the Local REST API key and updated the current-user Codex credential (value hidden).'
  if [[ "$NO_SECRET_IMPORT" -eq 1 ]]; then echo "Set $SECRET_ENV_NAME to the new plugin key before restarting Codex."; else echo 'Restart Obsidian and Codex, then run doctor.'; fi
  exit 0
fi

REMOVE_OWNED_SECRET=0
if [[ "$NO_SECRET_IMPORT" -ne 1 && -n "$OLD_KEY" ]]; then
  CURRENT_KEY="$(launchctl getenv "$SECRET_ENV_NAME" 2>/dev/null || true)"
  MANAGED_ZSH_KEY="$(read_managed_zsh_key)"
  [[ -z "$CURRENT_KEY" || "$CURRENT_KEY" == "$OLD_KEY" ]] || { echo "$SECRET_ENV_NAME does not match this Vault; refusing to remove it." >&2; exit 1; }
  [[ -z "$MANAGED_ZSH_KEY" || "$MANAGED_ZSH_KEY" == "$OLD_KEY" ]] || { echo "$SECRET_ENV_NAME in the managed .zshenv block does not match this Vault; refusing to remove it." >&2; exit 1; }
  REMOVE_OWNED_SECRET=1
fi

if [[ -f "$DATA_PATH" ]]; then STAGED_DATA="$WORK_DIR/data.json"; stage_data "$DATA_PATH" "$STAGED_DATA" '' 0; commit_replace "$STAGED_DATA" "$DATA_PATH"; fi
if [[ -f "$CODEX_CONFIG_PATH" ]]; then STAGED_CONFIG="$WORK_DIR/config.toml"; stage_config_without_mcp "$CODEX_CONFIG_PATH" "$STAGED_CONFIG"; commit_replace "$STAGED_CONFIG" "$CODEX_CONFIG_PATH"; fi

if [[ "$ACTION" == 'uninstall' ]]; then
  if [[ -f "$COMMUNITY_PATH" ]]; then STAGED_COMMUNITY="$WORK_DIR/community-plugins.json"; stage_community_without_plugin "$COMMUNITY_PATH" "$STAGED_COMMUNITY"; commit_replace "$STAGED_COMMUNITY" "$COMMUNITY_PATH"; fi
  commit_delete "$PLUGIN_DIR"
  commit_delete "$SETTINGS_PATH"
fi

if [[ "$REMOVE_OWNED_SECRET" -eq 1 ]]; then
  update_zshenv remove
  if [[ -n "$OLD_KEY" && "$CURRENT_KEY" == "$OLD_KEY" ]]; then launchctl unsetenv "$SECRET_ENV_NAME"; fi
  unset "$SECRET_ENV_NAME" 2>/dev/null || true
fi
COMMIT_SUCCESS=1

if [[ "$ACTION" == 'disconnect' ]]; then
  echo 'Disconnected Codex from the selected Vault and disabled the HTTP fallback. Obsidian plugin files and knowledge notes were preserved.'
else
  echo 'Removed the Local REST API plugin files and Codex integration settings for the selected Vault. Knowledge notes were preserved.'
fi
