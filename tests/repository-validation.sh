#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

for script in scripts/bootstrap.sh scripts/doctor.sh scripts/install-plugin.sh tests/repository-validation.sh; do
  bash -n "$script"
done

python3 - "$repo_root" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
metadata = json.loads((root / "scripts" / "upstream-assets.json").read_text(encoding="utf-8"))
assert metadata["pluginId"] == "obsidian-local-rest-api"
assert metadata["version"] == "5.1.0"
for name in ("main.js", "manifest.json", "styles.css"):
    assert re.fullmatch(r"[0-9a-f]{64}", metadata["assets"][name]), name

plugin_installer = (root / "scripts" / "install-plugin.sh").read_text(encoding="utf-8")
assert 'plugin_name="$(json_field' in plugin_installer
assert "plugin_name='codex-obsidian-knowledge'" not in plugin_installer
assert "CODEX_HOME:-$HOME/.codex" in plugin_installer

bootstrap = (root / "scripts" / "bootstrap.sh").read_text(encoding="utf-8")
assert "shasum -a 256" in bootstrap
assert "original files were restored" in bootstrap
assert "127.0.0.1:27123/mcp/" in bootstrap

doctor = (root / "scripts" / "doctor.sh").read_text(encoding="utf-8")
assert 'method' in doctor and 'initialize' in doctor
assert "bearer_token_env_var" in doctor
PY

bash scripts/bootstrap.sh --help >/dev/null
bash scripts/doctor.sh --help >/dev/null
echo 'Shell repository validation passed.'
