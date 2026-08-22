# Development guide

## Repository conventions

保持项目通用：不得把真实项目名、真实 Vault 路径、API key、个人用户名或机器专属路径写进 Skill、模板和脚本。示例路径使用 `C:\path\to\your\vault` 等占位形式。

Skill 的任务边界写在 `skills/code-knowledge-capture/SKILL.md`；长格式约束和安全规则放在 `references/`，不要把所有细节堆进入口文件。

## Change the note schema

先更新 `skills/code-knowledge-capture/references/summary-schema.md`，再同步更新 `templates/`、`README.md` 和 `docs/architecture.md` 中的结构示例。新字段应说明用途、是否必填以及兼容旧笔记的行为。`NoteRoot` 必须保持为 Vault 内的相对路径。

## Change the capture behavior

修改 Skill 时保持以下不变量：

- 明确触发，不能让普通代码问答触发写入。
- 先预览，后确认，确认前只读。
- 不删除笔记、不覆盖无关段落、不修改源代码仓库。
- 事实、推断、验证证据和未来计划分开记录。
- 写入后回读验证。

## Test locally

使用 Python 运行 Skill 和插件校验器：

```powershell
$skillValidator = 'C:\Users\ASUS\.codex\skills\.system\skill-creator\scripts\quick_validate.py'
$pluginValidator = 'C:\Users\ASUS\.codex\skills\.system\plugin-creator\scripts\validate_plugin.py'
& 'C:\Python314\python.exe' $skillValidator '.\skills\code-knowledge-capture'
& 'C:\Python314\python.exe' $pluginValidator '.'
```

解析 PowerShell 脚本而不执行真实写入：

```powershell
foreach ($path in @('.\scripts\install.ps1', '.\scripts\doctor.ps1')) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path), [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "$path has PowerShell parse errors" }
}
```

集成测试应使用临时测试 Vault，验证插件配置解析、配置幂等性、HTTP/HTTPS endpoint 检查和失败时不泄露 key。不要把真实 Vault API key 用作测试 fixture。
