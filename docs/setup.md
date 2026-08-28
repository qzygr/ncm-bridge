# 安装与登录

## 文档说明

该文档用于指导Agent安装@music163/ncm-cli并验证其可用性。

## 前置运行环境

- Windows，非Windows环境请立即停止运行本SKILL
- PowerShell
- Node.js >= 18

> **运行环境：PowerShell**（本 SKILL 中所有命令均基于 PowerShell 语法）

## 安装流程

### 第一步：运行安装流程

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\workflows\install-ncm-cli.ps1 -Json
```

该脚本会：

- 检查 Node.js >= 18、npm 与现有 ncm-cli。
- 在 ncm-cli 缺失时使用 npm 全局安装。
- 固定设置 `player=mpv`，仅用于满足 ncm-cli 内部校验；项目不会通过 mpv 播放。
- 只读执行 `ncm-cli login --check` 并返回 `OK` 或 `LOGIN_REQUIRED`。
- 不接收、不写入、不输出 `appId` 或 `privateKey`，也不会打开登录窗口。

默认情况下，已安装的 ncm-cli 会被保留，不会升级。需要升级时显式添加 `-Upgrade`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\workflows\install-ncm-cli.ps1 -Upgrade -Json
```

预览安装计划时使用 `-DryRun`；需要同时运行离线 fast 自检时添加 `-RunFastCheck`。两者可以组合使用，但 dry-run 不会执行自检。

### 第二步：配置 API Key

使用 ncm-cli 需要先设置 API Key。
请提示用户前往：[网易云音乐开放平台](https://developer.music.163.com/st/developer/apply/account?type=INDIVIDUAL)申请 API Key（appId 和 privateKey），在提供appId和privateKey后运行：

```powershell
ncm-cli config set appId <你的AppId>
ncm-cli config set privateKey <你的PrivateKey>
```

### 第三步：登录

登录是必须的，必须使用下列命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\workflows\start-ncm-cli-login.ps1 -Json
```

未登录时，该脚本只在可见登录窗口进程已经启动后才返回 `LOGIN_WINDOW_STARTED`。此时应暂停自动化流程，等待用户扫码完成并确认后，再继续验证登录状态。

验证登录状态：

```powershell
ncm-cli login --check
```

> 实际登录状态以 `ncm-cli login --check` 为准。`ncm-cli state` 只反映客户端/播放状态，不用于判断账号登录。
> 在未登录状态下，`ncm-cli` 可能隐藏或缺失部分子命令；排查 `playlist`、`search`、`commands`、`--help` 输出异常前，必须先完成 `ncm-cli login --check`。

### 第四步：整体验证

完成 API Key 配置与扫码登录后，再执行安装流程检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\workflows\install-ncm-cli.ps1 -RunFastCheck -Json
```

结果为 `code: OK` 且 `fastCheck.Success: true` 时，基础环境、登录状态和离线脚本自检均已通过。不要使用 `ncm-cli config list` 作为常规验证，因为它可能显示本机已保存的敏感配置。

若当前仓库可用，优先使用统一自检脚本：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\tests\test-ncm-bridge.ps1
```

解释规则如下：

- 全部通过：环境、登录状态、关键脚本与命令注册表均已就绪
- 若 `account login status` 失败：不要继续执行后续命令，也不要根据缺失命令判断版本或脚本问题；重新执行“第三步：登录”。执行后暂停当前任务，等待用户扫码完成，再重新运行自检脚本。

## 常见问题

| 问题                           | 解决方法                                                                 |
|------------------------------|--------------------------------------------------------------------------|
| `ncm-cli: command not found` | 检查 npm 全局 bin 是否在 PATH 中。PowerShell 中执行：`npm bin -g`            |
| 已安装旧版本，需要升级 | 使用 `install-ncm-cli.ps1 -Upgrade`；默认流程会保留现有版本。 |
| `mpv not found`              | 忽略，该方案不会使用 mpv 内置播放器                                          |
| 登录超时                         | 使用 `start-ncm-cli-login.ps1` 启动可见登录窗口，再等待扫码完成 |
| 编码乱码（PowerShell）            | 执行时显式使用UTF-8          |
