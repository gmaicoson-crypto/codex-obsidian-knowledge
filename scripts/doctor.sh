#!/usr/bin/env bash
set -euo pipefail

VAULT_PATH=""
CODEX_CONFIG_PATH="${HOME}/.codex/config.toml"
ALLOW_INSECURE_HTTP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault) VAULT_PATH="${2:?Missing value for --vault}"; shift 2 ;;
    --codex-config) CODEX_CONFIG_PATH="${2:?Missing value for --codex-config}"; shift 2 ;;
    --allow-insecure-http) ALLOW_INSECURE_HTTP=1; shift ;;
    -h|--help)
      echo 'Usage: ./scripts/doctor.sh --vault /absolute/path/to/vault [--allow-insecure-http]'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

failures=0
check() {
  local name="$1"; local passed="$2"; local detail="$3"
  if [[ "$passed" == '1' ]]; then
    printf '[OK]   %s: %s\n' "$name" "$detail"
  else
    printf '[FAIL] %s: %s\n' "$name" "$detail"
    failures=$((failures + 1))
  fi
}

[[ -n "$VAULT_PATH" ]] || { echo 'Vault path is required.' >&2; exit 2; }
[[ -d "$VAULT_PATH" ]] || { echo "Vault directory does not exist: $VAULT_PATH" >&2; exit 2; }

plugin_dir="$VAULT_PATH/.obsidian/plugins/obsidian-local-rest-api"
check 'Plugin files' "$([[ -f "$plugin_dir/main.js" && -f "$plugin_dir/manifest.json" ]] && echo 1 || echo 0)" "$plugin_dir"
check 'Plugin enabled' "$(grep -q 'obsidian-local-rest-api' "$VAULT_PATH/.obsidian/community-plugins.json" 2>/dev/null && echo 1 || echo 0)" "$VAULT_PATH/.obsidian/community-plugins.json"
api_key="$(grep -o '"apiKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$plugin_dir/data.json" 2>/dev/null | head -n 1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/' || true)"
check 'Plugin API key' "$([[ -n "$api_key" ]] && echo 1 || echo 0)" 'value hidden'
check 'Codex config' "$([[ -f "$CODEX_CONFIG_PATH" ]] && echo 1 || echo 0)" "$CODEX_CONFIG_PATH"
check 'Codex MCP section' "$(grep -q '^\[mcp_servers\.obsidian\]$' "$CODEX_CONFIG_PATH" 2>/dev/null && echo 1 || echo 0)" '[mcp_servers.obsidian]'

endpoint='https://127.0.0.1:27124/'
curl_args=(--fail --silent --show-error --max-time 3 -k -H "Authorization: Bearer $api_key")
if [[ "$ALLOW_INSECURE_HTTP" -eq 1 ]]; then
  endpoint='http://127.0.0.1:27123/'
  curl_args=(--fail --silent --show-error --max-time 3 -H "Authorization: Bearer $api_key")
fi
if [[ -n "$api_key" ]] && curl "${curl_args[@]}" "$endpoint" >/dev/null 2>&1; then
  check 'Obsidian endpoint' 1 "$endpoint"
else
  check 'Obsidian endpoint' 0 "$endpoint (is Obsidian open and is the plugin loaded?)"
fi

if [[ "$failures" -gt 0 ]]; then
  echo
  echo "Doctor found $failures issue(s)."
  exit 1
fi
echo
echo 'Doctor checks passed.'
