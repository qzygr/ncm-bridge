---
name: ncm-cli-setup
description: 安装和配置 ncm-cli（网易云音乐 CLI 工具）。当用户需要安装 ncm-cli、配置 API Key，或排查安装问题时，使用此 skill。
---

# ncm-cli 安装配置

ncm-cli 是网易云音乐的 CLI 工具（音乐搜索、播放控制、歌单管理、TUI 播放器（此处不使用））。

> **运行环境：PowerShell**（本 SKILL 中所有命令均基于 PowerShell 语法）

## 安装流程

### 第一步：安装 ncm-cli

```powershell
npm install -g @music163/ncm-cli
```

验证安装：

```powershell
ncm-cli --version
```

### 第二步：配置 API Key

使用 ncm-cli 需要先设置 API Key：

```powershell
ncm-cli config set appId <你的AppId>
ncm-cli config set privateKey <你的PrivateKey>
```


> 如果还没有 API Key，请先前往[网易云音乐开放平台](https://developer.music.163.com/st/developer/apply/account?type=INDIVIDUAL)申请 API Key（appId 和 privateKey）。

### 第三步：配置默认播放器

```powershell
ncm-cli config set player mpv
```

> 注意：此处设定 `mpv` 仅为满足 CLI 内部校验，实际不会调用 mpv 进行播放。

### 第四步：登录

登录是必须的，请使用：

```powershell
Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'
```

执行后会在桌面弹出 PowerShell 登录窗口。此时应暂停自动化流程，等待用户扫码完成并确认后，再继续验证登录状态。

验证登录状态：

```powershell
ncm-cli login --check
```

> 实际登录状态以 `ncm-cli login --check` 为准。`ncm-cli state` 只反映客户端/播放状态，不用于判断账号登录。
> 在未登录状态下，`ncm-cli` 可能隐藏或缺失部分子命令；排查 `playlist`、`search`、`commands`、`--help` 输出异常前，必须先完成 `ncm-cli login --check`。

### 第五步：整体验证

确认各项配置均就绪后，可执行以下命令做一次全面检查：

```powershell
ncm-cli --version; ncm-cli config list; ncm-cli login --check
```

三项均正常返回即为安装成功。

若当前仓库可用，优先使用统一自检脚本：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-ncm-bridge.ps1
```

解释规则如下：

- `9/9` 通过：环境、登录状态、关键脚本与命令注册表均已就绪
- 若 `account login status` 失败：不要继续执行后续命令，也不要根据缺失命令判断版本或脚本问题；改用桌面弹窗登录流程

```powershell
Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'
```

执行后暂停当前任务，等待用户扫码完成，再重新运行自检脚本。

## 常见问题

| 问题                           | 解决方法                                                                 |
|------------------------------|--------------------------------------------------------------------------|
| `ncm-cli: command not found` | 检查 npm 全局 bin 是否在 PATH 中。PowerShell 中执行：`npm bin -g`            |
| `mpv not found`              | 忽略，该方案不会使用 mpv 内置播放器                                          |
| 登录超时                         | 使用 `Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'` 弹出登录窗口 |
| 编码乱码（PowerShell）            | 执行前先设置：`[Console]::OutputEncoding = [Text.Encoding]::UTF8`          |

## 基本信息

- 需要 **Node.js >= 18**
- 运行环境：**PowerShell**（cmd 不适用）
