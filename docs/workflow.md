# Workflow

## First-run integration setup

当仓库被 Codex 打开时，先由 `AGENTS.md` 检查本地 Obsidian MCP 是否已经可用。若不可用，Codex 必须先解释以下变更并取得用户确认：下载第三方 Local REST API 插件、修改选定 Vault 的 `.obsidian` 配置、生成 API key、更新用户级 Codex MCP 配置。

确认后在 Windows 执行 `scripts/bootstrap.ps1 -Approve`，在 macOS 执行 `bash scripts/bootstrap.sh --approve`。多个 Vault 时让用户选择；无法自动识别时只询问 Vault 的绝对路径。安装完成后重启 Obsidian 和 Codex，并运行对应 doctor 脚本。连接未通过诊断前，不得声称已同步或写入 Obsidian。

## 触发与范围

普通代码问答、代码修改和调试不会自动写入知识库。只有用户明确提出总结、沉淀、归档或写入 Obsidian 时，Skill 才进入捕获流程。

默认范围是当前 Codex 任务和当前工作区。若项目名、功能边界或目标 Vault 不明确，应先询问一个简短问题，而不是猜测或读取无关对话。

## Preview-first 流程

```text
明确触发
    ↓
只读收集对话、仓库和验证证据
    ↓
识别项目、功能、状态与重复内容
    ↓
展示新增/更新笔记预览
    ↓  用户确认
通过 Obsidian MCP 写入
    ↓
回读并报告实际路径、状态和未验证边界
```

预览至少包含：项目名、功能名、拟写入路径、当前状态、实现事实、关键代码实例（代码块 + 文件路径/符号）、验证证据、不确定项、敏感信息脱敏结果以及会新增或更新的笔记。若没有可引用的源代码，必须明确标注“无可引用代码实例”及原因。

## Status model

| Status | Meaning |
|---|---|
| `analysis` | 只有调查或现状理解，没有形成实现 |
| `design` | 已提出方案，但尚未有代码或配置变更 |
| `implemented` | 已有代码/配置变更，但验证不完整 |
| `verified` | 相关实现、测试和所声称的运行场景均有证据 |
| `blocked` | 因明确记录的阻塞项无法继续 |

不能因为“构建成功”就声称真实用户流程已验证。验证边界必须写进 `02-实施效果.md`。

## Incremental updates

第一次沉淀创建项目总览和功能目录。再次讨论同一功能时，使用 `project`、`feature`、`source_thread_id` 和内容指纹识别重复；预览对现有笔记的增量更新，并保留历史证据和已确认结论。

项目总览只保留稳定结论、功能状态矩阵、风险和索引，不复制功能笔记的全部实现细节。

## Writing contract

写入必须使用 Obsidian MCP 的结构化读写工具。MCP 不可用时，只报告连接配置或诊断错误，不把本地文件写入伪装成已同步到 Obsidian。写入完成后回读目标笔记，核对路径和内容状态。
