# DeskRelay for Codex 内测用户指南

本文面向参与内测的普通用户，目标是帮助你在自己的电脑和 iPhone 上完成安装、配对和日常使用。请按顺序操作；如果中途遇到问题，可以直接把本文末尾“反馈时请提供的信息”发给测试负责人。

## 你需要准备什么

开始前，请确认你已经具备以下条件：

- 一台可以正常使用 Codex 的 Mac 或 Windows 电脑。
- 一台已安装 DeskRelay for Codex 内测版的 iPhone。
- 测试负责人分配给你的专属公网地址，例如 `u001.example.com`。
- Mac 上可以打开“终端”；Windows 上可以打开 PowerShell。
- Mac 安装路径要求本机已有 Node.js 和 `pnpm`；Windows 安装脚本会优先自动补齐 Node.js、`pnpm` 和 `cloudflared`。
- 如果你需要使用 ChatGPT Web 板块，还需要电脑上安装 Chrome，并且已经能正常登录 `https://chatgpt.com/`。

每个内测用户都应使用自己的公网地址、自己的访问密钥和自己的 Companion。请不要多人共用同一个公网地址，也不要把二维码或访问密钥转发给别人。

## 一句话理解它怎么工作

DeskRelay for Codex 不是一个单独运行的手机 App。它由三部分组成：

- iPhone App：负责显示会话、发送消息、查看状态和处理审批。
- Companion：运行在你的 Mac 或 Windows 后台，负责把 iPhone 和电脑上的 Codex 连接起来。
- 电脑上的 Codex：真正执行你的会话和任务。

因此，iPhone 上看到的项目和对话来自你自己的电脑。连接成功后如果首页是空的，通常表示这台电脑当前没有可见的 Codex 项目或会话，而不是你应该看到某个共享云端历史。

## 第一步：安装 Companion

测试负责人会给你一个专属公网地址。下面命令里的 `<你的专属公网地址>` 需要替换成实际地址，例如 `u001.example.com`。

### Mac

在 Mac 上打开“终端”，执行：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/danxizuo/007Codex-companion/main/scripts/install-companion.sh)" -- --domain <你的专属公网地址>
```

如果测试负责人同时给了你 Cloudflare token，请使用下面这种形式：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/danxizuo/007Codex-companion/main/scripts/install-companion.sh)" -- --domain <你的专属公网地址> --cloudflared-token <测试负责人提供的 token>
```

### Windows

在 Windows 上打开 PowerShell，执行测试负责人分配给你的 Windows 专用命令。命令形态如下：

```powershell
$installer=Join-Path $env:TEMP "install-companion-windows.ps1"; Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/danxizuo/007Codex-companion/main/scripts/install-companion-windows.ps1" -OutFile $installer; powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Domain <你的专属公网地址> -CloudflaredToken <测试负责人提供的 token>
```

Windows 专用命令会自动下载或修复缺失的 `cloudflared`、Node.js、`pnpm`、Codex app-server 运行时和 Companion，并在成功后直接显示二维码。不要只运行 `cloudflared tunnel run`，因为它只会启动公网转发，不会安装 Companion，也不会显示二维码。

安装过程会自动完成这些事情：

- 下载并安装 Companion。
- 把 Companion 注册成后台服务。
- 自动选择可用端口，优先使用 `3939`。
- 生成访问密钥。
- 显示 iPhone 配对二维码。
- 检查本机服务是否可用，并尽量检查公网地址是否可用。

看到终端里出现配对二维码后，不要关闭终端窗口，先进行下一步扫码。

## 第二步：用 iPhone 扫码配对

在 iPhone 上打开 DeskRelay for Codex：

1. 进入设置页。
2. 点击“扫描配对二维码”。
3. 扫描电脑终端里显示的二维码。
4. 保存后回到首页，等待刷新。

二维码会同时保存公网地址和局域网地址。通常建议：

- 在外网或蜂窝网络下使用公网地址。
- iPhone 和电脑在同一个 Wi-Fi 下时，可以使用局域网地址，速度通常更快。

如果二维码已经从终端窗口里滚出，可以在 Mac 终端执行：

```bash
bash ~/.deskrelay-companion/app/scripts/show-companion-pairing.sh
```

Windows 用户可以在 PowerShell 执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.deskrelay-companion\app\scripts\show-companion-pairing-windows.ps1"
```

如果 iPhone 提示二维码无效，请重新执行上面的显示二维码命令。Windows 用户如果仍然无效，请重新运行测试负责人给你的 Windows 专用安装命令，让电脑下载最新 Companion 包后再扫码。

## 第三步：开始使用

配对完成后，你可以在 iPhone 上进行这些操作：

- 查看电脑上 Codex 里可见的项目和会话。
- 打开会话详情，查看回复、运行状态、文件变化和过程信息。
- 从 iPhone 发送新消息或继续已有会话。
- 在需要时点击停止，终止正在运行的任务。
- 处理需要你确认的审批请求。
- 使用听写把语音转成输入文字。

使用时请注意：

- 电脑需要开机并联网。
- Companion 需要保持运行。
- 电脑上 Codex 的登录状态、项目可见性和会话执行状态会影响 iPhone 端显示。
- iPhone 首页显示的是你这台电脑上可见的内容，不是所有内测用户共享的历史。

## 可选：启用 ChatGPT Web 板块

如果你需要使用 ChatGPT Web 板块，请完成下面步骤：

1. 安装 Companion 后，终端会显示 Chrome 插件入口。
2. 按终端提示安装 Chrome 插件。
3. 在 Chrome 打开 `https://chatgpt.com/` 并保持登录。
4. 回到 iPhone 的 ChatGPT 板块使用。

ChatGPT Web 板块使用的是你自己 Chrome 里已经登录的 ChatGPT 网页。它不会使用你的 OpenAI API，也不会把 ChatGPT 对话混入普通 Codex 项目。

## 常用维护命令

如果 iPhone 显示连接异常，或测试负责人让你重启 Companion，请按你的系统执行对应命令。

Mac：

```bash
bash ~/.deskrelay-companion/app/scripts/start-companion-service.sh
```

Windows：

```powershell
$installer=Join-Path $env:TEMP "install-companion-windows.ps1"; Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/danxizuo/007Codex-companion/main/scripts/install-companion-windows.ps1" -OutFile $installer; powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Domain <你的专属公网地址> -CloudflaredToken <测试负责人提供的 token>
```

如果只需要重新显示配对二维码，请执行：

Mac：

```bash
bash ~/.deskrelay-companion/app/scripts/show-companion-pairing.sh
```

Windows：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.deskrelay-companion\app\scripts\show-companion-pairing-windows.ps1"
```

如果需要卸载 Companion，但保留配置和访问密钥，请执行：

```bash
bash ~/.deskrelay-companion/app/scripts/uninstall-companion.sh
```

如果需要彻底卸载并删除本机配置，请执行：

```bash
bash ~/.deskrelay-companion/app/scripts/uninstall-companion.sh --remove-data
```

## 常见问题

### iPhone 显示离线

请先确认电脑已开机、联网，并执行一次对应系统的 Companion 启动或修复命令。

Mac：

```bash
bash ~/.deskrelay-companion/app/scripts/start-companion-service.sh
```

如果同一 Wi-Fi 下可以连接，但公网地址不能连接，请把公网地址和终端输出发给测试负责人。

### 首页没有项目或对话

这通常表示你的电脑上 Codex 当前没有可见的项目或会话。请先在电脑上打开 Codex，确认侧边栏里是否有项目或历史对话。iPhone 不会显示其他用户的历史，也不会显示测试负责人电脑上的历史。

### 发送后长时间没有回复

请确认电脑没有睡眠，Codex 能正常运行，并观察 iPhone 详情页是否显示运行状态。如果一直没有变化，请记录发送时间、会话标题和当时网络环境，再反馈给测试负责人。

### ChatGPT Web 没有响应

请确认 Chrome 插件已经安装，Chrome 里 `https://chatgpt.com/` 已登录，并且网页本身可以正常发送消息。

### 安装命令提示缺少 Node.js 或 pnpm

请先把终端里的提示截图或复制给测试负责人。不要反复执行安装命令，以免产生重复排查信息。

## 反馈时请提供的信息

遇到问题时，请尽量一次性提供这些信息：

- 你的专属公网地址。
- 问题发生的准确时间。
- 当时使用的是公网地址还是局域网地址。
- iPhone 型号和 iOS 版本。
- 电脑型号和系统版本。
- 你正在做什么操作，例如安装、扫码、刷新首页、发送消息、停止任务或使用 ChatGPT。
- iPhone 截图或录屏。
- 电脑终端最后显示的几行内容。
- 如果方便，请附上这个目录里的相关日志：`~/Library/Logs/DeskRelayCompanion/`。

请不要把二维码、访问密钥或包含私人会话内容的完整日志发到公开群里。

## 安全提醒

- 不要共享自己的二维码、访问密钥或公网地址。
- 不要让多人共用同一个 Companion。
- 如果电脑丢失、转让或不再参加内测，请执行彻底卸载命令。
- 公网地址只是连接入口，真正的数据来自你自己的电脑；电脑断网、睡眠或 Companion 停止时，iPhone 端也会失去连接。
