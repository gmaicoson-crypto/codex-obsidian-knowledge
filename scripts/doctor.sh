#!/usr/bin/env bash
set -euo pipefail

VAULT_PATH=""
CODEX_CONFIG_PATH="${CODEX_HOME:-$HOME/.codex}/config.toml"
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

section=''
if [[ -f "$CODEX_CONFIG_PATH" ]]; then
  section="$(awk '/^\[mcp_servers\.obsidian\]$/{inside=1; next} /^\[/{inside=0} inside{print}' "$CODEX_CONFIG_PATH")"
fi
check 'Codex MCP section' "$([[ -n "$section" ]] && echo 1 || echo 0)" '[mcp_servers.obsidian]'

endpoint="$(printf '%s\n' "$section" | sed -nE 's/^[[:space:]]*url[[:space:]]*=[[:space:]]*"([^"]+)"[[:space:]]*$/\1/p' | head -n 1)"
configured_env_name="$(printf '%s\n' "$section" | sed -nE 's/^[[:space:]]*bearer_token_env_var[[:space:]]*=[[:space:]]*"([A-Za-z_][A-Za-z0-9_]*)"[[:space:]]*$/\1/p' | head -n 1)"
check 'Codex MCP endpoint' "$([[ -n "$endpoint" ]] && echo 1 || echo 0)" "${endpoint:-missing url entry}"
check 'Codex API key variable name' "$([[ -n "$configured_env_name" ]] && echo 1 || echo 0)" "${configured_env_name:-missing bearer_token_env_var entry}"

codex_api_key=''
if [[ -n "$configured_env_name" ]]; then
  codex_api_key="$(printenv "$configured_env_name" 2>/dev/null || true)"
  if [[ -z "$codex_api_key" ]] && command -v launchctl >/dev/null 2>&1; then
    codex_api_key="$(launchctl getenv "$configured_env_name" 2>/dev/null || true)"
  fi
fi
check 'Codex API key variable' "$([[ -n "$codex_api_key" ]] && echo 1 || echo 0)" 'value hidden'
keys_match=0
if [[ -n "$api_key" && -n "$codex_api_key" && "$api_key" == "$codex_api_key" ]]; then
  keys_match=1
fi
check 'API key match' "$keys_match" 'Plugin and Codex credential sources must agree (values hidden)'

endpoint_is_supported=0
if [[ "$endpoint" == https://127.0.0.1:* || "$endpoint" == http://127.0.0.1:* ]]; then
  endpoint_is_supported=1
fi
check 'Endpoint boundary' "$endpoint_is_supported" "${endpoint:-missing endpoint}"
if [[ "$ALLOW_INSECURE_HTTP" -eq 1 ]]; then
  check 'HTTP fallback selection' "$([[ "$endpoint" == http://127.0.0.1:* ]] && echo 1 || echo 0)" "${endpoint:-missing endpoint}"
fi

mcp_body='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"codex-obsidian-knowledge-doctor","version":"0.1.0"}}}'
curl_args=(--fail --silent --show-error --max-time 5 -H "Authorization: Bearer $codex_api_key" -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' --data "$mcp_body")
if [[ "$endpoint_is_supported" -eq 1 && "$keys_match" -eq 1 ]]; then
  response=''
  if response="$(curl "${curl_args[@]}" "$endpoint" 2>/dev/null)" && printf '%s\n' "$response" | grep -q '"result"'; then
    check 'MCP initialize' 1 'Authenticated JSON-RPC response received'
  elif [[ "$endpoint" == https://* ]]; then
    insecure_response=''
    if insecure_response="$(curl -k "${curl_args[@]}" "$endpoint" 2>/dev/null)" && printf '%s\n' "$insecure_response" | grep -q '"serverInfo"'; then
      check 'MCP initialize' 0 'The server responded only when TLS verification was disabled; trust the Local REST API certificate or use the HTTP fallback'
    else
      check 'MCP initialize' 0 'Request failed; check Obsidian, the configured endpoint, and API key'
    fi
  else
    check 'MCP initialize' 0 'Request failed; check Obsidian, the configured endpoint, API key, and HTTP-server setting'
  fi
else
  check 'MCP initialize' 0 'Skipped because the configured endpoint or credential does not match the plugin'
fi

if [[ "$failures" -gt 0 ]]; then
  echo
  echo "Doctor found $failures issue(s)."
  exit 1
fi
echo
echo 'Doctor checks passed.'
