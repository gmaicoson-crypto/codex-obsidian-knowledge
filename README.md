# Codex Obsidian Knowledge

把 Codex 写出的代码变成初级程序员能读懂、能验证、能复用的 Obsidian 学习笔记。项目按照“项目导读 + 架构与术语 + 功能代码导读”的结构沉淀知识，不绑定某个项目、仓库或本机 Vault。

本项目主要面向正在使用 Codex 智能体写代码的初级程序员。它不是简单保存“改了哪些文件”，而是帮助读者理解关键名词、项目架构、功能实现原理、真实调用链、设计权衡、调试方法和验证边界，并通过自测问题与安全的小练习确认自己是否真的理解。

## What it does

当用户明确提出“将本次代码对话进行知识总结沉淀”或类似请求时，`code-knowledge-capture` Skill 会：

1. 读取当前对话、当前项目和可用的测试/构建证据。
2. 提炼学习目标、前置知识、关键术语、架构心智模型和端到端代码路径。
3. 用“通俗理解 + 本项目真实代码证据”两层方式生成待写入内容预览。
4. 加入调试入口、验证边界、自测问题和带预期结果的安全练习。
5. 等待用户明确确认，例如“确认写入”。
6. 通过已连接的 Obsidian MCP 创建或更新 Markdown 知识卡片，并回读报告实际结果。

默认不会因为普通代码讨论而自动写入，也不会删除笔记或修改源代码。

## Quick start

第一次使用请按[从 Git clone 到首次使用](docs/getting-started.md)操作，流程包括：

1. 克隆仓库并在 Codex 中打开；
2. 安装本仓库提供的 Codex 插件；
3. 经确认后初始化 Obsidian 的 Local REST API 连接；
4. 重启 Obsidian 和 Codex，运行 doctor；
5. 在新对话中先预览知识总结，再确认写入。

如果只想了解首次安装会修改哪些本机配置，请先阅读该指南的“初始化 Obsidian 连接”部分。

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

每个功能目录分别记录目标与状态、实现细节、实施效果、可复用知识、后续迭代和证据来源。默认使用 `schema_version: 2`、`capture_mode: expanded`、`audience: beginner-programmer` 和 `detail_level: expanded`。每次沉淀还记录 `note_kind`、`capture_id`、`evidence_hash`、`source_commit` 和 `verified_at`，用于查询、迁移、证据锚定和幂等更新。

项目级 `01-架构与术语.md` 从系统边界、组件地图、主流程三个层次解释架构，并维护与真实代码位置关联的术语表。功能级 `01-实现细节.md` 沿一个具体输入跟读调用链，`03-知识应用总结.md` 则沉淀术语、可迁移知识、常见误解、调试方法和练习。

除完整的 `expanded` 外，还支持 `compact`（小改动的三篇功能笔记）、`architecture-only`（只维护项目架构）和 `update-only`（只补丁已有笔记）。模式必须出现在预览中；切换到精简模式不会删除既有笔记。

## Prerequisites

用户只需要安装：

- Codex Desktop/CLI；
- Obsidian 桌面版 1.13.1 或更高版本，并至少创建或打开一个 Vault（固定依赖的 Local REST API 5.1.0 要求该最低版本）。

当前写入流程支持 Windows 和 macOS 本地 Codex 环境。Linux/WSL、ChatGPT Web/移动端和 Codex 云端不能直接访问桌面回环 endpoint；详见[平台支持矩阵](docs/platform-support.md)。

首次使用时，本仓库的 Codex 指令会先请求用户确认，然后自动下载并启用 Obsidian 社区插件 `Local REST API with MCP`，校验固定资产哈希，生成本机 API key，并配置 Codex 的本地 MCP 连接。用户无需预先安装 Node.js、Python 或其他 MCP server。

## Codex plugin distribution

仓库包含 `.agents/plugins/marketplace.json` 和自动安装脚本。用户可以直接把本地项目文件夹或开源仓库地址交给 Codex，并明确要求“将这个仓库安装为 Codex 插件”；Codex 会读取 `AGENTS.md`，在确认后执行安装脚本。用户不需要手动创建 `~/.agents/plugins/marketplace.json`，也不需要把插件复制到 `~/.codex/plugins`。

示例请求：

```text
请把当前文件夹（或这个仓库地址）安装为 Codex 插件并启用。先说明将修改的 Codex 配置范围，确认后执行仓库里的安装入口。
```

安装脚本会先从仓库源文件生成被 `.gitignore` 忽略的标准 `plugins/codex-obsidian-knowledge` 分发目录，再注册仓库 marketplace 并调用 Codex CLI 安装。这样 marketplace 使用 `./plugins/<plugin-name>` 布局，同时仓库仍只维护一份源文件。清单使用 `AVAILABLE`，避免客户端在用户只是打开仓库时绕过安全检查自动写入插件缓存；只有 Codex 根据明确的安装请求执行脚本时才会安装。插件安装失败时，本轮新注册的 marketplace 会被回滚。

安装前会检查同名 marketplace 和 Codex 插件缓存。如果发现它们已经指向其他位置，或目标缓存目录已存在但不能确认是本插件，脚本会停止并报告冲突，不会覆盖、删除或替换用户已有的插件文件。

Codex 也可以直接执行以下入口：

```powershell
.\scripts\install-plugin.ps1 -Approve
```

macOS：

```bash
bash ./scripts/install-plugin.sh --approve
```

这一步只负责分发和加载 Codex 插件。Obsidian 的 `Local REST API with MCP` 属于第三方软件，仍必须遵循首次运行时的确认、安装和诊断流程，不能静默绕过。

## First-run setup

当 Codex 打开本仓库后，如果发现 Obsidian 连接尚未准备好，应先说明将要修改的范围并请求确认。确认后：

```powershell
.\scripts\bootstrap.ps1 -Approve
```

macOS：

```bash
bash ./scripts/bootstrap.sh --approve
```

脚本会自动完成：

1. 从固定版本的 Local REST API GitHub Release 下载 `main.js`、`manifest.json` 和 `styles.css`，并校验 `scripts/upstream-assets.json` 中的 SHA-256；
2. 识别 Obsidian Vault；多个 Vault 时让用户选择；
3. 将插件放入 `<vault>/.obsidian/plugins/obsidian-local-rest-api/`；
4. 启用社区插件并写入 API key；
5. 配置 Codex 的 `[mcp_servers.obsidian]`；
6. 将知识笔记根目录写入 `<vault>/.codex-obsidian-knowledge.json`；所有 Vault、插件和 Codex 配置变更先进入临时区，提交失败时恢复原文件。

如果有多个 Vault，也可以直接指定路径：

```powershell
.\scripts\bootstrap.ps1 -VaultPath 'C:\path\to\your\vault' -Approve
```

```bash
bash ./scripts/bootstrap.sh --vault '/Users/you/Obsidian/MyVault' --approve
```

首次安装后需要重启一次 Obsidian，使其加载刚下载的插件，然后重启 Codex。诊断命令：

```powershell
.\scripts\doctor.ps1 -VaultPath 'C:\path\to\your\vault'
```

```bash
bash ./scripts/doctor.sh --vault '/Users/you/Obsidian/MyVault'
```

默认使用插件的 HTTPS MCP endpoint `https://127.0.0.1:27124/mcp/`。如果客户端无法信任插件的自签名证书，可以选择仅绑定本机回环地址的 HTTP fallback：

```powershell
.\scripts\bootstrap.ps1 -VaultPath 'C:\path\to\your\vault' -Approve -AllowInsecureHttp
```

```bash
bash ./scripts/bootstrap.sh --vault '/Users/you/Obsidian/MyVault' --approve --allow-insecure-http
```

HTTP fallback 仍使用 Bearer API key，只接受 `127.0.0.1`，不要将 endpoint 暴露到局域网或公网。
bootstrap 会在用户明确选择 fallback 时同步启用插件的回环 HTTP server；doctor 会读取 Codex 的实际 MCP 配置和环境变量，并执行经过认证的 MCP `initialize` 请求。

HTTPS 模式会明确关闭 HTTP server。若配置与插件状态漂移，可在确认后执行 `doctor.ps1 -Repair -Approve` 或 `doctor.sh --repair --approve` 修复。

Windows 和 macOS 脚本都遵守 `CODEX_HOME`；macOS 默认还会为 GUI/新 zsh 进程维护 `~/.zshenv` 中的受标记凭据块。若不希望脚本持久化环境变量，可使用 `-NoSecretImport` 或 `--no-secret-import`，然后在启动 Codex 前自行设置 `OBSIDIAN_LOCAL_REST_API_KEY`。

## Use the Skill

当本仓库的 marketplace 已加载后，在代码讨论完成时明确触发：

```text
将本次代码对话进行知识总结沉淀，先给我预览，不要立即写入。
```

小改动可以指定：

```text
使用 code-knowledge-capture 的 compact 模式沉淀本次修复，先预览。
```

检查预览中的项目、功能、状态、目标路径、学习目标、前置知识、术语、架构心智模型、端到端流程、决策权衡、验证边界、自测练习和不确定项。确认后再说：

```text
确认写入。
```

如果同一功能已经存在，Skill 应生成更新预览，而不是重复创建第二套笔记。若证据不足，笔记应明确写出 `未验证`、`无证据` 或 `[待确认]`，不能用泛化描述填充细节。

## Repository map

| Path | Purpose |
|---|---|
| `.agents/plugins/marketplace.json` | 仓库级 Codex marketplace，自动暴露本插件 |
| `scripts/build-plugin-package.*` | 生成 marketplace 使用的标准插件分发目录 |
| `AGENTS.md` | 告诉 Codex 如何进行首次检测、确认和跨平台初始化 |
| `docs/getting-started.md` | 从 `git clone` 到首次使用的完整上手流程 |
| `skills/code-knowledge-capture/` | 面向初学者的 Codex 知识提炼 Skill、教学规则和审核策略 |
| `templates/` | 项目导读、架构术语、代码导读、验证、自测练习等笔记模板 |
| `scripts/bootstrap.ps1` | Windows 自动安装插件、生成 key 并配置 Codex MCP |
| `scripts/bootstrap.sh` | macOS 自动安装插件、生成 key 并配置 Codex MCP |
| `scripts/upstream-assets.json` | 固定上游版本、下载地址和资产 SHA-256 |
| `scripts/install-plugin.ps1` / `scripts/install-plugin.sh` | 由 Codex 执行的本仓库插件安装入口 |
| `scripts/install.ps1` | 已安装插件时的 Windows 连接配置脚本 |
| `scripts/doctor.ps1` / `scripts/doctor.sh` | 检查插件、endpoint、环境变量和 MCP 配置 |
| `scripts/rotate-key.*` / `disconnect.*` / `uninstall.*` | 密钥轮换、断开连接和保留笔记的卸载流程 |
| `scripts/scan-sensitive-content.ps1` | 写入前扫描候选 Markdown 中的凭据和敏感内容 |
| `scripts/new-evidence-identity.*` | 规范化脱敏证据清单，并生成稳定的 SHA-256 与 capture ID |
| `scripts/validate-note-path.ps1` | 校验 Vault 内的 noteRoot、项目 ID 和功能 ID |
| `tests/` 和 `.github/workflows/ci.yml` | Windows/macOS 仓库验证和持续集成 |
| `tests/skill-evals/` | 代表性 Skill 行为用例和结构化输出契约 |
| `PRIVACY.md` | 数据流、保留、删除和第三方边界 |
| `docs/platform-support.md` | 支持平台和远程环境限制 |
| `docs/demo.md` | 预览优先的示例交互 |
| `docs/workflow.md` | 从对话到知识沉淀的完整流程 |
| `docs/development.md` | 如何扩展 Skill、模板和脚本 |
| `docs/security.md` | 凭据、HTTP fallback 和写入边界 |

## Privacy and safety

默认只处理用户明确指定的当前对话和当前项目。写入前必须展示预览并获得确认。API key、密码、token、cookie、私钥和未脱敏个人标识不得进入 Obsidian 笔记或 Git 仓库；应以 `[REDACTED]` 替代。

项目和功能目录使用安全 slug；写入前必须验证完整目标路径，并通过敏感内容扫描。扫描失败会阻止写入，不会只作为提示继续执行。

本项目只负责 Codex Skill、模板和连接配置；它不上传对话，不托管 Obsidian Vault，也不提供远程服务器。

完整的数据处理和删除说明见 [PRIVACY.md](PRIVACY.md)。非敏感问题可通过仓库 Issues 反馈；漏洞请使用 GitHub Security Advisories，不要在公开报告中附带 key 或 Vault 内容。

## Connection lifecycle

以下命令都要求再次确认，并且不会删除知识笔记：

```powershell
.\scripts\rotate-key.ps1 -VaultPath 'C:\path\to\your\vault' -Approve
.\scripts\disconnect.ps1 -VaultPath 'C:\path\to\your\vault' -Approve
.\scripts\uninstall.ps1 -VaultPath 'C:\path\to\your\vault' -Approve
```

```bash
bash ./scripts/rotate-key.sh --vault '/Users/you/Obsidian/MyVault' --approve
bash ./scripts/disconnect.sh --vault '/Users/you/Obsidian/MyVault' --approve
bash ./scripts/uninstall.sh --vault '/Users/you/Obsidian/MyVault' --approve
```

`disconnect` 保留第三方插件和集成设置，只移除 Codex 连接并关闭 HTTP fallback；`uninstall` 移除选定 Vault 的第三方插件文件和集成设置，但保留 Markdown 知识笔记。

## License

MIT License。详见 [LICENSE](LICENSE)。
