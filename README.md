# Codex Obsidian Knowledge

将 Codex 中经过讨论和实现的代码知识，按“项目总览 + 功能开发目录”的结构沉淀到 Obsidian。本项目是通用的开源 Codex 插件包，不绑定某个项目、仓库或本机 Vault。

## What it does

当用户明确提出“将本次代码对话进行知识总结沉淀”或类似请求时，`code-knowledge-capture` Skill 会：

1. 读取当前对话、当前项目和可用的测试/构建证据。
2. 推断项目与功能，生成待写入内容预览。
3. 等待用户明确确认，例如“确认写入”。
4. 通过已连接的 Obsidian MCP 创建或更新 Markdown 知识卡片。
5. 回读目标笔记，报告实际写入的路径和结果。

默认不会因为普通代码讨论而自动写入，也不会删除笔记或修改源代码。

## Output layout

```text
<project>/
├── 00-项目总览.md
├── 01-架构与术语.md
└── features/<feature>/
    ├── 00-功能总览.md
    ├── 01-实现细节.md
    ├── 02-实施效果.md
    ├── 03-知识应用总结.md
    ├── 04-后续迭代方向.md
    └── 99-相关对话与文件.md
```

每个功能目录分别记录目标与状态、实现细节、实施效果、可复用知识、后续迭代和证据来源，便于复盘、检索和持续升级。

## Prerequisites

- Windows 10/11、PowerShell 5.1 或 PowerShell 7。
- Obsidian 已安装并能打开目标 Vault。
- Obsidian 社区插件 `Local REST API` 已安装并启用，且其版本提供 MCP endpoint。
- Codex Desktop/CLI 支持本地 MCP 配置。

Local REST API 插件是独立依赖，不包含在本项目中。首次使用时，在 Obsidian 中启用插件并记录它生成的 API key；安装脚本会从 Vault 的插件配置中读取 key，并只保存到当前 Windows 用户环境变量，不会把 key 写入仓库。

## Install the connection

在本仓库根目录执行，替换为自己的 Vault 路径：

```powershell
.\scripts\install.ps1 -VaultPath 'C:\path\to\your\vault'
```

脚本默认把知识笔记写入 Vault 下的 `Codex知识库`，并在 Vault 根目录保存 `.codex-obsidian-knowledge.json`。可以通过 `-NoteRoot` 自定义相对路径，例如：

```powershell
.\scripts\install.ps1 `
  -VaultPath 'C:\path\to\your\vault' `
  -NoteRoot '知识库\代码沉淀'
```

脚本默认配置插件的 HTTPS MCP endpoint `https://127.0.0.1:27124/mcp/`。如果本机客户端无法信任插件的自签名证书，可以使用仅绑定本机回环地址的 HTTP fallback：

```powershell
.\scripts\install.ps1 -VaultPath 'C:\path\to\your\vault' -NoteRoot 'Codex知识库' -AllowInsecureHttp
```

重启 Codex 后运行诊断：

```powershell
.\scripts\doctor.ps1 -VaultPath 'C:\path\to\your\vault'
```

若使用 HTTP fallback，API key 仍通过 Bearer header 发送，只接受 `127.0.0.1`，不要把该 endpoint 暴露到局域网或公网。

## Use the Skill

把本插件包安装到 Codex 的插件/Skill 目录后，在代码讨论完成时明确触发：

```text
将本次代码对话进行知识总结沉淀，先给我预览，不要立即写入。
```

检查预览中的项目、功能、状态、目标路径、证据和不确定项。确认后再说：

```text
确认写入。
```

如果同一功能已经存在，Skill 应生成更新预览，而不是重复创建第二套笔记。

## Repository map

| Path | Purpose |
|---|---|
| `skills/code-knowledge-capture/` | 可复用 Codex Skill、知识模式和审核策略 |
| `templates/` | 项目与功能笔记模板 |
| `scripts/install.ps1` | 从 Vault 配置 MCP 和安全导入 API key |
| `scripts/doctor.ps1` | 检查插件、endpoint、环境变量和 MCP 握手 |
| `docs/workflow.md` | 从对话到知识沉淀的完整流程 |
| `docs/development.md` | 如何扩展 Skill、模板和脚本 |
| `docs/security.md` | 凭据、HTTP fallback 和写入边界 |

## Privacy and safety

默认只处理用户明确指定的当前对话和当前项目。写入前必须展示预览并获得确认。API key、密码、token、cookie、私钥和未脱敏个人标识不得进入 Obsidian 笔记或 Git 仓库；应以 `[REDACTED]` 替代。

本项目只负责 Codex Skill、模板和连接配置；它不上传对话，不托管 Obsidian Vault，也不提供远程服务器。

## License

MIT License。详见 [LICENSE](LICENSE)。
