# Getting started

本指南面向第一次使用本项目的用户，覆盖从 `git clone` 到在 Codex 中完成第一次知识沉淀。

## 前置条件

请先准备：

- Windows 或 macOS。当前自动初始化脚本支持这两个平台；
- Git；
- Codex Desktop/CLI。执行仓库安装脚本时，`codex` 命令需要在 `PATH` 中；
- Obsidian 桌面版 1.13.1 或更高版本，并至少创建或打开一个 Vault；
- 首次初始化时可以访问 GitHub，用于下载第三方 `Local REST API with MCP` Obsidian 插件。

不需要预先安装 Node.js、Python 或其他 MCP server。

## 从 Git clone 到首次使用

### 1. 克隆仓库


```bash
git clone https://github.com/gmaicoson-crypto/codex-obsidian-knowledge.git
cd codex-obsidian-knowledge
```

### 2. 安装 Codex 插件

在 Codex 中打开刚刚克隆的仓库，明确请求安装当前仓库提供的 Codex 插件。也可以在仓库根目录的终端中执行对应脚本。

可以直接发送下面的请求，让 Codex 先说明影响范围，再等待你的确认：

```text
请把当前文件夹安装为 Codex 插件并启用。先说明将修改的 Codex 配置和插件缓存范围，等我确认后再执行仓库里的安装入口。
```

安装会注册本地 Codex marketplace，并更新当前用户的 Codex 配置和插件缓存。确认这些变更后再执行：

```powershell
.\scripts\install-plugin.ps1 -Approve
```

macOS：

```bash
bash ./scripts/install-plugin.sh --approve
```

安装完成后，重启 Codex，并在新对话中测试。安装脚本发现同名 marketplace 或插件缓存指向其他位置时会停止，不会覆盖已有内容。

### 3. 初始化 Obsidian 连接

这一步只需首次执行，但会产生真实的本机配置变更。脚本会：

- 下载并启用第三方 `Local REST API with MCP` Obsidian 插件；
- 修改选定 Vault 的 `.obsidian` 设置；
- 生成或复用本机 API key；
- 更新 Codex 用户级 MCP 配置；
- 写入 Vault 根目录的 `.codex-obsidian-knowledge.json`。

确认上述范围后，在仓库根目录执行：

```powershell
.\scripts\bootstrap.ps1 -Approve
```

macOS：

```bash
bash ./scripts/bootstrap.sh --approve
```

脚本会优先识别 Obsidian 中唯一或当前打开的 Vault。检测到多个 Vault 时会让你选择；也可以直接传入 Vault 的绝对路径：

```powershell
.\scripts\bootstrap.ps1 `
  -VaultPath 'C:\path\to\your\vault' `
  -Approve
```

macOS：

```bash
bash ./scripts/bootstrap.sh \
  --vault '/Users/you/Obsidian/MyVault' \
  --approve
```

默认优先使用只绑定到 `127.0.0.1` 的 HTTPS MCP endpoint。如果客户端无法信任 Local REST API 的本机自签名证书，可以显式选择 HTTP fallback：

```powershell
.\scripts\bootstrap.ps1 `
  -VaultPath 'C:\path\to\your\vault' `
  -Approve `
  -AllowInsecureHttp
```

```bash
bash ./scripts/bootstrap.sh \
  --vault '/Users/you/Obsidian/MyVault' \
  --approve \
  --allow-insecure-http
```

HTTP fallback 仍只监听 `127.0.0.1` 并使用 Bearer API key，不要把它暴露到局域网或公网。

### 4. 重启并运行诊断

初始化完成后：

1. 重启 Obsidian，使其加载刚下载的插件；
2. 重启 Codex，使其重新加载 MCP 配置和环境变量；
3. 在仓库根目录运行诊断脚本。

Windows：

```powershell
.\scripts\doctor.ps1 -VaultPath 'C:\path\to\your\vault'
```

macOS：

```bash
bash ./scripts/doctor.sh --vault '/Users/you/Obsidian/MyVault'
```

看到 `Doctor checks passed.` 后，才表示 Obsidian MCP 连接已通过检查，可以进行知识写入。

### 5. 完成第一次知识沉淀

在 Codex 的新对话中明确触发 Skill，并要求先预览：

```text
将本次代码对话进行知识总结沉淀，先给我预览，不要立即写入。
```

检查预览中的项目、功能、状态、目标路径、实现事实、验证证据和不确定项。确认内容无误后，再发送：

```text
确认写入。
```

首次写入会在配置的 Vault 笔记根目录下创建项目总览和功能知识目录。普通代码问答、调试和代码修改不会自动写入 Obsidian。

## 常见问题

### 找不到 `codex` 命令

请从 Codex 安装提供的终端环境执行脚本，或直接在 Codex 中打开仓库并请求它安装当前插件。安装脚本必须能够调用 Codex CLI。

### 找不到或选错 Vault

使用 `-VaultPath` 或 `--vault` 传入 Vault 的绝对路径。路径必须是实际存在的目录。

### MCP initialize 失败

先确认 Obsidian 正在运行、社区插件已启用，并在 bootstrap 后重启过 Obsidian 和 Codex。若 HTTPS 失败是因为本机证书不受信任，再显式使用 `-AllowInsecureHttp` 或 `--allow-insecure-http` 重新初始化，然后重新运行 doctor。

### 安装时报 marketplace 或缓存冲突

不要删除或覆盖现有目录。安装脚本检测到同名 marketplace 或缓存已经指向其他位置时会主动停止；应先检查现有 Codex 插件配置，再决定是否由用户手动解决冲突。

## 后续使用

以后只需在 Codex 中完成代码讨论，并在需要归档时重复“先预览、后确认”的两句话。若更换电脑、Vault 或 Codex 配置，重新执行对应的 bootstrap 和 doctor 流程即可。
