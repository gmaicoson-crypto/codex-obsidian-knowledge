# Architecture

## Components

```text
Codex conversation
      │ explicit capture request
      ▼
code-knowledge-capture Skill
      │ read-only evidence + preview
      ▼
User confirmation
      │ approved note operations
      ▼
Codex MCP client ── Bearer token ──> Obsidian Local REST API MCP endpoint
                                             │
                                             ▼
                                      Obsidian Vault Markdown
```

首次打开仓库时，根目录 `AGENTS.md` 负责发现连接状态。用户确认后，`bootstrap.ps1` 或 `bootstrap.sh` 下载并启用 Local REST API 插件、生成本地 API key，并配置 Codex MCP。之后 Skill 才使用本机 endpoint。

本仓库把 Skill、笔记模式、连接安装和诊断脚本放在一个发布单元里；它不实现或托管一个新的远程 MCP 服务。MCP 服务由 Obsidian 的 Local REST API 社区插件提供，Codex 通过本机 endpoint 调用它。安装脚本先预检配置，再在临时目录完成下载、哈希和 manifest 校验，最后以可回滚提交更新 Vault 与 Codex 配置。

## Capture path

1. Skill 判断用户是否明确要求知识沉淀。
2. Skill 只读收集当前任务、当前项目、变更文件、测试/构建证据和已有目标笔记。
3. Skill 同时建立证据地图和学习地图。证据地图将结论分为 `[事实]`、`[推断]`、`[计划]`、`[待确认]`；学习地图识别前置知识、关键术语、架构心智模型、真实代码路径、调试入口和自测目标。
4. Skill 生成脱敏、排序后的规范证据清单，计算 `evidence_hash` 和稳定 `capture_id`，并记录源 commit；匹配现有身份且内容无变化时返回 no-op。
5. Skill 按“通俗理解 → 本项目中的文件/符号/数据流证据”组织解释，展示捕获模式、拟创建或更新的项目总览、架构术语、功能笔记和来源索引，并选择 `analysis`、`design`、`implemented`、`verified` 或 `blocked` 状态。
6. 用户确认后，Codex 使用 Obsidian MCP 的结构化工具创建目录对应的 Markdown 笔记；更新已有功能时只提交预览中批准的增量。
7. Skill 回读笔记，核对路径、frontmatter 和关键内容，再向用户报告结果。

## Learning model

默认读者标记为 `audience: beginner-programmer`。知识结构分成三个层次：

1. 项目层解释用途、最小运行/观察入口、阅读顺序和功能学习路线；
2. 架构层用系统边界、组件地图、编号主流程和项目术语表建立整体模型；
3. 功能层用一个具体输入贯穿入口、核心逻辑、状态/输出、验证和调试路径，再通过解释题与安全练习进行理解检查。

这一模型不降低证据标准。通俗解释必须能回指到真实文件、符号、配置、测试或对话；无法确认的架构或原理必须标为推断或未验证。

## Connection path

`scripts/bootstrap.ps1` / `scripts/bootstrap.sh` 首次配置目标 Vault 中的：

```text
<vault>/.obsidian/plugins/obsidian-local-rest-api/data.json
```

它保留或生成 API key，保存到当前用户的 `OBSIDIAN_LOCAL_REST_API_KEY` 环境变量，在 Vault 根目录写入 `.codex-obsidian-knowledge.json` 保存 `noteRoot`，并在 Codex 配置中写入：

```toml
[mcp_servers.obsidian]
url = "https://127.0.0.1:27124/mcp/"
bearer_token_env_var = "OBSIDIAN_LOCAL_REST_API_KEY"
startup_timeout_sec = 20
tool_timeout_sec = 60
```

当自签名 HTTPS 证书无法被客户端信任时，`-AllowInsecureHttp` 或 `--allow-insecure-http` 会启用插件的回环 HTTP server，并将 endpoint 切换到 `http://127.0.0.1:27123/mcp/`。诊断脚本读取 Codex 的实际配置和凭据来源，核对插件身份、启用状态、API key、超时、回环边界，并执行经过认证且结构完整的 MCP `initialize` 请求；HTTPS 证书不受信任时诊断会失败并提示信任证书或改用 HTTP fallback。

协议状态是双向约束：HTTP endpoint 要求 `enableInsecureServer=true`，HTTPS endpoint 要求 `false`。doctor 会检测漂移，只有显式 `Repair + Approve` 才会修改插件状态和凭据来源。

## Data ownership

| Data | Owner | Stored where |
|---|---|---|
| Skill instructions and templates | This repository | GitHub/Codex plugin package |
| API key | User | User environment and Obsidian plugin settings |
| Coding evidence and summaries | User | Obsidian Vault |
| MCP transport | Local REST API plugin | `127.0.0.1` endpoint |

对话内容不会因为安装本项目而上传到本仓库或第三方服务。实际是否读取某个仓库文件、某个对话范围或某条 Obsidian 笔记，仍由当前 Codex 任务和用户明确请求决定。
