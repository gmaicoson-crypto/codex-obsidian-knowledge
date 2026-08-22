# Security model

## Secret handling

首次初始化脚本从 Local REST API 插件的 `data.json` 读取或生成 API key，只将它写入当前用户的 `OBSIDIAN_LOCAL_REST_API_KEY` 环境变量和插件自己的 `data.json`。脚本输出只显示变量名和 endpoint，不显示 key。不要提交 `.env`、插件运行状态或诊断日志。

初始化必须经过用户确认。脚本当前固定从 Local REST API `5.1.0` GitHub Release 下载 `main.js`、`manifest.json` 和 `styles.css`，不执行下载内容之外的安装器，也不把 API key 写入仓库。升级上游插件版本时应同步审查并更新这个固定版本。

知识沉淀阶段必须脱敏 API key、密码、Bearer token、cookie、私钥和个人标识。笔记可以记录“使用了凭据”这一事实，但不能记录凭据值。

## Network boundary

HTTPS endpoint 是首选。Local REST API 通常使用本机自签名证书，某些 MCP 客户端可能无法自动信任它。`-AllowInsecureHttp` 只为此兼容性问题提供 fallback：HTTP 仅绑定 `127.0.0.1`，仍通过 Bearer token 鉴权，不能改成 `0.0.0.0` 或对外转发。

如果 endpoint 被代理、端口被占用或插件关闭，诊断脚本应失败并指出下一步，不应打印敏感配置。

## Write boundary

捕获 Skill 只写入用户确认的 Obsidian 目标笔记。它不删除笔记、不覆盖无关段落、不修改源代码、不执行部署，也不把本地路径之外的内容上传到第三方服务。

## Threats and mitigations

| Threat | Mitigation |
|---|---|
| 未经同意安装第三方插件 | 首次初始化前展示范围并要求明确确认 |
| 误写或过早写入 | 明确触发 + preview-first + explicit confirmation |
| 重复创建知识 | project/feature/source thread/content hash 去重 |
| 把推断当事实 | 分开记录证据、不确定项和验证边界 |
| 凭据进入笔记或仓库 | 写入前脱敏、脚本不打印 key、Git ignore 本地状态 |
| HTTP endpoint 暴露 | 仅回环地址 + Bearer token + HTTPS 优先 |
