# Development guide

## Repository conventions

保持项目通用：不得把真实项目名、真实 Vault 路径、API key、个人用户名或机器专属路径写进 Skill、模板和脚本。示例路径使用 `C:\path\to\your\vault` 等占位形式。

Skill 的任务边界写在 `skills/code-knowledge-capture/SKILL.md`；长格式约束和安全规则放在 `references/`，不要把所有细节堆进入口文件。

## Change the note schema

先更新 `skills/code-knowledge-capture/references/summary-schema.md`，再同步更新 `templates/`、`README.md`、`docs/workflow.md` 和 `docs/architecture.md` 中的结构示例。新字段应说明用途、是否必填以及兼容旧笔记的行为；当前 schema version 为 2，使用 `note_kind`、`capture_id`、`evidence_hash`、`source_commit` 和 `verified_at`。旧笔记缺少新字段时仍可读取和增量迁移。`NoteRoot`、project ID 和 feature ID 必须遵守 `path-policy.md`；写入前必须遵守 `redaction-policy.md`。

捕获模式定义集中在 `references/capture-modes.md`。新增或改变模式时，必须同步模板选择规则、README、工作流文档和代表性行为用例；模式降级不能删除已有笔记。

面向初学者的解释规则集中在 `references/beginner-learning-guide.md`。模板应保持以下教学不变量：先给通俗心智模型再给技术证据；术语关联真实代码位置；实现导读说明输入、处理、输出和失败信号；练习给出预期观察并保持只读或可安全回退。不要把模板扩展成通用编程教材。

## Change the capture behavior

修改 Skill 时保持以下不变量：

- 明确触发，不能让普通代码问答触发写入。
- 先预览，后确认，确认前只读。
- 不删除笔记、不覆盖无关段落、不修改源代码仓库。
- 事实、推断、验证证据和未来计划分开记录。
- 初学者解释不牺牲技术准确性，并始终关联项目证据。
- 自测与练习验证理解，不要求接触生产数据、凭据或破坏性操作。
- 写入后回读验证。

## Test locally

使用当前 Codex Home 和 PATH 中的 Python 运行 Skill 和插件校验器：

```powershell
$codexRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$python = (Get-Command python -ErrorAction Stop).Source
$skillValidator = Join-Path $codexRoot 'skills\.system\skill-creator\scripts\quick_validate.py'
$pluginValidator = Join-Path $codexRoot 'skills\.system\plugin-creator\scripts\validate_plugin.py'
& $python -X utf8 $skillValidator '.\skills\code-knowledge-capture'
& $python -X utf8 $pluginValidator '.'
```

生成标准 marketplace 包并用真实 Codex CLI 在隔离的 `CODEX_HOME` 中安装、重复安装和卸载：

```powershell
.\scripts\build-plugin-package.ps1
.\tests\codex-cli-validation.ps1
```

运行仓库校验和隔离的临时 Vault 回归测试（测试数据仅创建在 `tests/.tmp-*` 并在结束时清理）：

```powershell
.\tests\repository-validation.ps1
```

Skill 行为用例会在 CI 中做确定性契约校验。真实模型评测是显式、只读且可能消耗额度的本地步骤：

```powershell
.\tests\validate-skill-evals.ps1
.\tests\run-skill-evals.ps1 -ApproveCost
```

macOS 初始化脚本应在 macOS 测试机上执行语法检查和临时 Vault 集成测试。测试覆盖固定的 Local REST API 版本下载、首次生成 API key、已有 `data.json` 的幂等更新、`community-plugins.json` / `app.json` 配置、Codex MCP 配置以及 HTTPS/HTTP endpoint 检查。不要把真实 Vault API key 用作测试 fixture。

集成测试使用临时测试 Vault，验证插件配置解析、HTTP/HTTPS 状态一致性、密钥轮换、断开、保留笔记的卸载、失败回滚和失败时不泄露 key。每周 workflow 会重新下载固定上游资产并验证 SHA-256，同时只创建升级审查 issue，不自动替换 hash。

macOS 或 CI 环境还应运行：

```bash
bash -n scripts/*.sh tests/repository-validation.sh
bash tests/repository-validation.sh
shellcheck -S error scripts/*.sh tests/*.sh
```

发布前运行 `tests/release-validation.ps1`。`vX.Y.Z` tag 必须与 plugin manifest 和 CHANGELOG 一致；tag workflow 会生成源码归档及 SHA-256。GitHub Actions 必须固定到 commit SHA。
