# Companion GitHub 内测分发说明

本文记录不做图形安装器时的 Companion 分发方式。目标是让内测用户通过一条命令把 Companion 安装成 Mac 或 Windows 后台服务，并用你分配的 Cloudflare 子域名和二维码完成 iPhone 配对。

## 给内测用户的安装命令

你先为用户分配子域名，例如：

```text
u001.deskrelay.example.com
```

然后让用户在 Mac 终端执行：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/danxizuo/007Codex-companion/main/scripts/install-companion.sh)" -- --domain u001.deskrelay.example.com
```

如果你已经在 Cloudflare 为这个用户准备了 tunnel token，可以一并传入：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/danxizuo/007Codex-companion/main/scripts/install-companion.sh)" -- --domain u001.deskrelay.example.com --cloudflared-token <token>
```

如果用户机器上已经有可用的 named tunnel 配置，安装和后续短启动脚本会优先把 `--domain` 里的主机名补进本机 `cloudflared` ingress，并尝试写入 Cloudflare DNS 路由。
传入 `--cloudflared-token` 后，只有在本机没有可复用 named tunnel 配置时，安装脚本才会把 token tunnel 注册成用户级后台服务，并把它转发到当前选择的本机 Companion 端口。
安装脚本在本机服务健康后会先输出一个合并配对二维码，二维码内同时包含公网地址和可用时的局域网地址，然后再用公网地址访问 `/status`。如果公网地址没有返回 200，安装会提示公网入口未就绪，但用户仍然可以先用同一个二维码里保存的局域网地址连接。

安装完成后，脚本会输出二维码。用户在 iOS 设置页点“扫描配对二维码”，扫码后会自动保存地址和访问密钥。

当前二维码同时保留旧版 iPhone App 可识别的主地址字段和新版 App 使用的多地址字段。如果用户扫码提示“二维码无效”，先让用户重新运行安装命令或重新显示二维码，确保使用的是公开仓库最新 release 生成的二维码。

## Windows 专用安装命令

Windows 用户不要只运行 `cloudflared tunnel run`。那条命令只会启动公网转发，不会安装 Companion，也不会显示二维码。

给 Windows 用户分配 `w001.sci2web.top` 这类专属子域名和对应 Cloudflare token 后，让用户在 PowerShell 执行：

```powershell
$installer=Join-Path $env:TEMP "install-companion-windows.ps1"; Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/danxizuo/007Codex-companion/main/scripts/install-companion-windows.ps1" -OutFile $installer; powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Domain w001.sci2web.top -CloudflaredToken "<token>"
```

The installer and release archive are downloaded from the public repository `danxizuo/007Codex-companion`. Do not put a private GitHub token in the user-facing Windows install command.

这条命令会自动完成：

- 如果本机缺少 Node.js、pnpm 或 cloudflared，优先通过 `winget` 安装。
- 安装或修复 Windows 端 Codex app-server 运行时，并把真实 `codex.exe` 所在目录写入用户 PATH。
- 下载当前 GitHub Release 里的 Companion 包。
- 写入 Windows 本机配置和访问密钥。
- 注册 `DeskRelayCompanion` 计划任务，开机登录后自动启动 Companion。
- 注册 `DeskRelayTunnel-<子域名前缀>` 计划任务，把 Cloudflare 子域名转发到当前 Companion 端口。
- 验证本机 `/status`，尽量验证公网 `/status`，最后直接输出 iPhone 配对二维码。

如果需要重新显示二维码，执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.deskrelay-companion\app\scripts\show-companion-pairing-windows.ps1"
```

Windows 端安装后的位置：

| 内容 | 路径 |
| --- | --- |
| Companion app | `%USERPROFILE%\.deskrelay-companion\app` |
| 产品配置 | `%USERPROFILE%\.deskrelay-companion\config.json` |
| 访问密钥 | `%USERPROFILE%\.deskrelay-companion\auth-token` |
| 日志 | `%USERPROFILE%\.deskrelay-companion\logs` |
| 后台服务 | Windows 计划任务 `DeskRelayCompanion` |
| 公网隧道 | Windows 计划任务 `DeskRelayTunnel-<子域名前缀>` |

## ChatGPT 插件

ChatGPT 板块依赖用户自己电脑上的 Chrome 插件。Companion 安装成功后会同时输出 ChatGPT 插件入口：

- 如果已经配置 `DESKRELAY_CHATGPT_BRIDGE_WEBSTORE_URL`，脚本会显示 Chrome Web Store 安装链接。
- 如果还没有上架 Chrome Web Store，脚本会显示 GitHub Release 插件包下载地址，并提示本机可加载的插件目录：`~/.deskrelay-companion/app/apps/chrome-chatgpt-bridge`。

当前内测用户的最短路径是：

```text
安装 Companion -> 扫 iPhone 配对二维码 -> 安装 Chrome 插件 -> 打开 chatgpt.com 并登录
```

Chrome 插件只负责把手机端 ChatGPT 板块的请求交给已登录的 `chatgpt.com` 网页，再把网页回答回传给 Companion。它不使用 OpenAI API，也不会把 ChatGPT 对话写入普通 Codex 项目。

## 安装后的位置

| 内容 | 路径 |
| --- | --- |
| Companion checkout | `~/.deskrelay-companion/app` |
| 产品配置 | `~/.deskrelay-companion/config.json` |
| 访问密钥 | `~/.deskrelay-companion/auth-token` |
| 后台服务 | `~/Library/LaunchAgents/com.deskrelay.codex.companion.plist` |
| 日志 | `~/Library/Logs/DeskRelayCompanion/` |

后台服务默认监听 `0.0.0.0`，用于支持同一局域网内的 iPhone 直连；端口由安装脚本自动选择并写入 `~/.deskrelay-companion/config.json`。公网访问应通过你给用户分配的 Cloudflare 子域名进入。

用户需要手动重启 Companion，或者安装后找不到二维码时，可以执行：

```bash
bash ~/.deskrelay-companion/app/scripts/start-companion-service.sh
```

这个脚本会自动选择可用端口、写回配置、重启后台服务并验活当前端口。
如果 Companion 配置里有公网地址，它还会同步更新 Cloudflare 转发目标并重新验公网 `/status`，避免端口变化后二维码地址和真实隧道脱节。
启动成功后，它会重新显示配对二维码和 ChatGPT 插件入口。

## 手动重新显示配对二维码

```bash
bash ~/.deskrelay-companion/app/scripts/show-companion-pairing.sh
```

## 卸载

保留配置和访问密钥：

```bash
bash ~/.deskrelay-companion/app/scripts/uninstall-companion.sh
```

连配置一起删除：

```bash
bash ~/.deskrelay-companion/app/scripts/uninstall-companion.sh --remove-data
```

## 发布包

如果不想让用户现场从源码构建，可以先生成 release 压缩包：

```bash
pnpm companion:package v0.1.0-beta.1
```

第一版安装脚本仍以 GitHub checkout 为主，release 压缩包用于后续把安装过程改成“下载已构建产物”。

ChatGPT 插件可以单独打包：

```bash
pnpm chatgpt-bridge:package v0.1.0-beta.2
```

发布到同一个 GitHub Release：

```bash
pnpm chatgpt-bridge:publish
```
