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

architecture = (root / "templates" / "architecture-and-terms.md").read_text(encoding="utf-8")
assert all(section in architecture for section in (
    "第一层：系统边界", "第二层：组件地图", "第三层：主流程", "关键术语表"
))

implementation = (root / "templates" / "implementation-details.md").read_text(encoding="utf-8")
assert all(section in implementation for section in (
    "端到端代码导读", "输入从哪里来", "关键语法/API", "失败信号"
))

knowledge = (root / "templates" / "knowledge-application.md").read_text(encoding="utf-8")
assert all(section in knowledge for section in (
    "本功能关键术语", "用自己的话检验理解", "动手练习", "预期观察/答案"
))

skill = (root / "skills" / "code-knowledge-capture" / "SKILL.md").read_text(encoding="utf-8")
guide_path = root / "skills" / "code-knowledge-capture" / "references" / "beginner-learning-guide.md"
skill_ui = (root / "skills" / "code-knowledge-capture" / "agents" / "openai.yaml").read_text(encoding="utf-8")
assert guide_path.is_file()
assert "beginner-learning-guide.md" in skill and "audience: beginner-programmer" in skill
assert "beginner-friendly" in skill_ui
assert "Use $code-knowledge-capture" in skill_ui
short_description = next(
    line.split('"', 2)[1]
    for line in skill_ui.splitlines()
    if line.strip().startswith("short_description:")
)
assert 25 <= len(short_description) <= 64
PY

bash scripts/bootstrap.sh --help >/dev/null
bash scripts/doctor.sh --help >/dev/null
echo 'Shell repository validation passed.'
