#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

for script in scripts/*.sh tests/*.sh; do
  bash -n "$script"
done

python3 - "$repo_root" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
unsupported_jxa_getenv = "$." + "getenv("
unsupported_jxa_console = "console." + "log("
for path in (*sorted((root / "scripts").glob("*.sh")), *sorted((root / "tests").glob("*.sh"))):
    shell_source = path.read_text(encoding="utf-8")
    assert unsupported_jxa_getenv not in shell_source, path
    assert unsupported_jxa_console not in shell_source, path

metadata = json.loads((root / "scripts" / "upstream-assets.json").read_text(encoding="utf-8"))
assert metadata["pluginId"] == "obsidian-local-rest-api"
assert metadata["version"] == "5.1.0"
for name in ("main.js", "manifest.json", "styles.css"):
    assert re.fullmatch(r"[0-9a-f]{64}", metadata["assets"][name]), name

plugin_installer = (root / "scripts" / "install-plugin.sh").read_text(encoding="utf-8")
assert 'plugin_name="$(json_field' in plugin_installer
assert "plugin_name='codex-obsidian-knowledge'" not in plugin_installer
assert "CODEX_HOME:-$HOME/.codex" in plugin_installer
assert "marketplace_added_by_this_run" in plugin_installer

bootstrap = (root / "scripts" / "bootstrap.sh").read_text(encoding="utf-8")
assert "shasum -a 256" in bootstrap
assert "original files were restored" in bootstrap
assert "127.0.0.1:27123/mcp/" in bootstrap
assert "data.enableInsecureServer = enableInsecureServer" in bootstrap

doctor = (root / "scripts" / "doctor.sh").read_text(encoding="utf-8")
assert 'method' in doctor and 'initialize' in doctor
assert "bearer_token_env_var" in doctor
assert "Plugin protocol mode" in doctor and "REPAIR=0" in doctor

feature_templates = (
    "feature-overview.md",
    "implementation-details.md",
    "implementation-effect.md",
    "iteration-roadmap.md",
    "knowledge-application.md",
    "source-index.md",
)
for name in feature_templates:
    content = (root / "templates" / name).read_text(encoding="utf-8")
    assert "type: code-feature-summary" in content, name
    assert "audience: beginner-programmer" in content, name
    assert "detail_level: expanded" in content, name
    assert "schema_version: 2" in content, name
    assert "capture_mode: expanded" in content, name
    assert "capture_id: <capture-id>" in content, name
    assert "evidence_hash: <sha256>" in content, name

architecture = (root / "templates" / "architecture-and-terms.md").read_text(encoding="utf-8")
assert all(section in architecture for section in (
    "第一层：系统边界", "第二层：组件地图", "第三层：主流程", "关键术语表"
))
assert "为什么这样分层" in architecture

implementation = (root / "templates" / "implementation-details.md").read_text(encoding="utf-8")
assert all(section in implementation for section in (
    "端到端代码导读", "输入从哪里来", "关键语法/API", "失败信号"
))
assert all(section in implementation for section in ("机制拆解", "反事实、边界与失败路径", "反事实/边界"))

effect = (root / "templates" / "implementation-effect.md").read_text(encoding="utf-8")
assert all(section in effect for section in ("证据如何支持结论", "关键假设与反例"))

knowledge = (root / "templates" / "knowledge-application.md").read_text(encoding="utf-8")
assert all(section in knowledge for section in (
    "本功能关键术语", "用自己的话检验理解", "动手练习", "预期观察/答案"
))
assert all(section in knowledge for section in ("机制推导", "反例或失败信号", "深度探究复盘"))

skill = (root / "skills" / "code-knowledge-capture" / "SKILL.md").read_text(encoding="utf-8")
guide_path = root / "skills" / "code-knowledge-capture" / "references" / "beginner-learning-guide.md"
deep_guide_path = root / "skills" / "code-knowledge-capture" / "references" / "deep-exploration-guide.md"
skill_ui = (root / "skills" / "code-knowledge-capture" / "agents" / "openai.yaml").read_text(encoding="utf-8")
assert guide_path.is_file()
assert deep_guide_path.is_file()
assert "beginner-learning-guide.md" in skill and "audience: beginner-programmer" in skill
deep_guide = deep_guide_path.read_text(encoding="utf-8")
assert "deep-exploration-guide.md" in skill and "深度探究审计" in skill
assert all(section in deep_guide for section in ("六遍探究流程", "反事实", "证据不足"))
assert "beginner-friendly" in skill_ui
assert "Use $code-knowledge-capture" in skill_ui
assert "capture-modes.md" in skill and "capture_id" in skill and "evidence_hash" in skill
assert "icon_small:" in skill_ui and "icon_large:" in skill_ui
short_description = next(
    line.split('"', 2)[1]
    for line in skill_ui.splitlines()
    if line.strip().startswith("short_description:")
)
assert 25 <= len(short_description) <= 64

manifest = json.loads((root / ".codex-plugin" / "plugin.json").read_text(encoding="utf-8"))
assert manifest["version"] == "0.3.0"
assert manifest["author"]["name"] == "gmaicoson-crypto"
for asset in (manifest["interface"]["composerIcon"], manifest["interface"]["logo"], manifest["interface"]["logoDark"], *manifest["interface"]["screenshots"]):
    assert (root / asset).is_file(), asset
assert (root / "PRIVACY.md").is_file()
marketplace = json.loads((root / ".agents" / "plugins" / "marketplace.json").read_text(encoding="utf-8"))
assert marketplace["plugins"][0]["source"]["path"] == "./plugins/codex-obsidian-knowledge"
assert (root / "scripts" / "build-plugin-package.sh").is_file()
assert (root / "scripts" / "new-evidence-identity.sh").is_file()

cases = json.loads((root / "tests" / "skill-evals" / "cases.json").read_text(encoding="utf-8"))
assert len(cases) >= 6
assert {case["id"] for case in cases} >= {
    "ordinary-explanation-does-not-capture",
    "design-compact-preview",
    "implemented-expanded-preview",
    "sensitive-evidence-is-redacted",
    "update-only-missing-target-blocks",
    "duplicate-evidence-is-noop",
    "expanded-depth-audit",
}
PY

bash scripts/bootstrap.sh --help >/dev/null
bash scripts/doctor.sh --help >/dev/null
bash scripts/connection-maintenance.sh --help >/dev/null

fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-obsidian-shell-tests.XXXXXX")"
cleanup() { [[ "$fixture_root" == "${TMPDIR:-/tmp}/codex-obsidian-shell-tests."* ]] && rm -rf -- "$fixture_root"; }
trap cleanup EXIT

identity_a="$fixture_root/evidence-a.json"
identity_b="$fixture_root/evidence-b.json"
printf '%s\n' '{"files":[{"path":"src/中文.ts","lines":[1,2]},{"path":"src/a.ts","lines":[3]}],"tests":["unit","integration"],"note":"line1\r\nline2"}' > "$identity_a"
printf '%s\n' '{"note":"line1\nline2","tests":["integration","unit"],"files":[{"lines":[3],"path":"src/a.ts"},{"lines":[1,2],"path":"src/中文.ts"}]}' > "$identity_b"
result_a="$(bash scripts/new-evidence-identity.sh --manifest "$identity_a" --project demo-project --feature feature-1 --thread 'thread/42' --source-commit ABCDEF1)"
result_b="$(bash scripts/new-evidence-identity.sh --manifest "$identity_b" --project demo-project --feature feature-1 --thread 'thread/42' --source-commit abcdef1)"
python3 - "$result_a" "$result_b" <<'PY'
import json, re, sys
a, b = json.loads(sys.argv[1]), json.loads(sys.argv[2])
assert a["evidence_hash"] == b["evidence_hash"]
assert a["evidence_hash"] == "ae050bd1978f16b0a3a8d464d373bbdda6125d3d0e345ef2694bec052f1ed414"
assert a["capture_id"] == b["capture_id"]
assert re.fullmatch(r"codex:thread-42:demo-project:feature-1:[0-9a-f]{16}", a["capture_id"])
assert a["source_commit"] == "abcdef1"
PY
sensitive_identity="$fixture_root/evidence-sensitive.json"
printf '%s\n' '{"request":"Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456"}' > "$sensitive_identity"
if bash scripts/new-evidence-identity.sh --manifest "$sensitive_identity" --project demo-project --feature feature-1 >/dev/null 2>&1; then
  echo 'Evidence identity helper hashed a sensitive manifest.' >&2
  exit 1
fi
path_like_identity="$fixture_root/evidence-path-like-secret.json"
printf '%s\n' '{"opaque":"segment/p9K2mQ7vR4xT8nL3cW6yH1sF5jD0uB9eG2aZ7qX4"}' > "$path_like_identity"
if bash scripts/new-evidence-identity.sh --manifest "$path_like_identity" --project demo-project --feature feature-1 >/dev/null 2>&1; then
  echo 'Evidence identity helper exempted an unlabeled high-entropy value because it contained a slash.' >&2
  exit 1
fi
url_identity="$fixture_root/evidence-url.json"
printf '%s\n' '{"source":"https://github.com/gmaicoson-crypto/codex-obsidian-knowledge/security/advisories/new"}' > "$url_identity"
bash scripts/new-evidence-identity.sh --manifest "$url_identity" --project demo-project --feature feature-1 >/dev/null

vault="$fixture_root/vault"
plugin_dir="$vault/.obsidian/plugins/obsidian-local-rest-api"
config="$fixture_root/codex/config.toml"
mkdir -p "$plugin_dir" "$(dirname "$config")" "$vault/Codex知识库/demo"
python3 - "$vault" "$config" <<'PY'
import json
import pathlib
import sys
vault = pathlib.Path(sys.argv[1])
config = pathlib.Path(sys.argv[2])
plugin = vault / ".obsidian" / "plugins" / "obsidian-local-rest-api"
(plugin / "manifest.json").write_text(json.dumps({"id": "obsidian-local-rest-api", "version": "5.1.0"}), encoding="utf-8")
(plugin / "main.js").write_text("/* fixture */\n", encoding="utf-8")
(plugin / "data.json").write_text(json.dumps({"apiKey": "shell-test-key", "enableInsecureServer": True}), encoding="utf-8")
(vault / ".obsidian" / "community-plugins.json").write_text(json.dumps(["obsidian-local-rest-api", "other-plugin"]), encoding="utf-8")
(vault / ".codex-obsidian-knowledge.json").write_text(json.dumps({"version": 1, "noteRoot": "Codex知识库"}), encoding="utf-8")
(vault / "Codex知识库" / "demo" / "00-项目总览.md").write_text("# preserve\n", encoding="utf-8")
config.write_text('[ui]\ntheme = "dark"\n\n[mcp_servers.obsidian]\nurl = "http://127.0.0.1:27123/mcp/"\nbearer_token_env_var = "OBSIDIAN_LOCAL_REST_API_KEY"\nstartup_timeout_sec = 20\ntool_timeout_sec = 60\n', encoding="utf-8")
PY

foreign_config="$fixture_root/codex/foreign-config.toml"
python3 - "$config" "$foreign_config" <<'PY'
import pathlib, sys
source, target = map(pathlib.Path, sys.argv[1:])
target.write_text(source.read_text().replace('OBSIDIAN_LOCAL_REST_API_KEY', 'OTHER_TOKEN'), encoding='utf-8')
PY
repair_home="$fixture_root/repair-home"
mkdir -p "$repair_home"
if HOME="$repair_home" bash scripts/doctor.sh --vault "$vault" --codex-config "$foreign_config" --allow-insecure-http --repair --approve >/dev/null 2>&1; then
  echo 'doctor.sh repaired a config that uses a foreign bearer_token_env_var.' >&2
  exit 1
fi
if HOME="$repair_home" OBSIDIAN_LOCAL_REST_API_KEY='foreign-process-key' bash scripts/doctor.sh --vault "$vault" --codex-config "$config" --allow-insecure-http --repair --approve >/dev/null 2>&1; then
  echo 'doctor.sh replaced a process credential owned by another Vault.' >&2
  exit 1
fi

foreign_home="$fixture_root/foreign-home"
mkdir -p "$foreign_home"
printf '%s\n' '# BEGIN codex-obsidian-knowledge' 'export OBSIDIAN_LOCAL_REST_API_KEY=another-vault-key' '# END codex-obsidian-knowledge' > "$foreign_home/.zshenv"
if HOME="$foreign_home" bash scripts/disconnect.sh --vault "$vault" --codex-config "$config" --approve >/dev/null 2>&1; then
  echo 'disconnect.sh removed a credential owned by another Vault.' >&2
  exit 1
fi
python3 - "$vault" "$config" <<'PY'
import json, pathlib, sys
vault, config = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
data = json.loads((vault / ".obsidian/plugins/obsidian-local-rest-api/data.json").read_text())
assert data["enableInsecureServer"] is True
assert "[mcp_servers.obsidian]" in config.read_text()
PY

bash scripts/disconnect.sh --vault "$vault" --codex-config "$config" --no-secret-import --approve >/dev/null
python3 - "$vault" "$config" <<'PY'
import json, pathlib, sys
vault, config = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
data = json.loads((vault / ".obsidian/plugins/obsidian-local-rest-api/data.json").read_text())
assert data["enableInsecureServer"] is False
text = config.read_text()
assert "[mcp_servers.obsidian]" not in text and "[ui]" in text
assert (vault / "Codex知识库/demo/00-项目总览.md").is_file()
PY

old_key="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["apiKey"])' "$plugin_dir/data.json")"
bash scripts/rotate-key.sh --vault "$vault" --codex-config "$config" --no-secret-import --approve >/dev/null
new_key="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["apiKey"])' "$plugin_dir/data.json")"
[[ -n "$new_key" && "$new_key" != "$old_key" ]]

bash scripts/uninstall.sh --vault "$vault" --codex-config "$config" --no-secret-import --approve >/dev/null
[[ ! -e "$plugin_dir" ]]
[[ ! -e "$vault/.codex-obsidian-knowledge.json" ]]
[[ -f "$vault/Codex知识库/demo/00-项目总览.md" ]]
python3 - "$vault" <<'PY'
import json, pathlib, sys
vault = pathlib.Path(sys.argv[1])
assert json.loads((vault / ".obsidian/community-plugins.json").read_text()) == ["other-plugin"]
PY

echo 'Shell repository validation passed.'
