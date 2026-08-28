---
name: ncm-bridge
description: 使用 ncm-bridge 安装和配置 ncm-cli，并安全地搜索网易云音乐、管理程序专用歌单、发起本地播放与验证播放结果。
---

# ncm-bridge

网易云音乐 Agent 桥接项目。`ncm-cli` 负责搜索和歌单管理，`orpheus://` 只负责向本地客户端发起控制请求，Windows SMTC 是唯一的播放验证来源。

## 环境与安装

- Windows、PowerShell 5+、Node.js >= 18。
- 已安装且可运行的网易云音乐客户端。
- 已安装 `@music163/ncm-cli`，并拥有网易云音乐开放平台 API Key。

```powershell
npm install -g @music163/ncm-cli
ncm-cli config set appId <AppId>
ncm-cli config set privateKey <PrivateKey>
ncm-cli config set player mpv
ncm-cli --version
```

`player mpv` 仅用于满足 ncm-cli 内部校验；本项目不会通过 mpv 播放。

登录必须在可见窗口中完成：

```powershell
Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'
```

用户扫码完成后，使用以下命令确认：

```powershell
ncm-cli login --check
```

如果登录失败，只启动登录窗口并停止当前流程。未登录状态下，禁止根据 `commands`、`--help`、`unknown command` 或缺失子命令判断 ncm-cli 版本和插件功能。

## 操作原则

1. 默认先执行离线自检：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\tests\test-ncm-bridge.ps1
   ```

2. 进行联网搜索、歌单操作、SMTC 读取或真实播放前，必须先使 `ncm-cli login --check` 成功。
3. Agent 默认只调用统一入口 `scripts\entry\invoke-ncm-bridge.ps1`，并优先使用 `-Json -CompressJson`。
4. `orpheus://` URL 发出、payload dry-run 或进程成功退出都不代表已经播放；只有 SMTC 验证可设置 `verified=true`。
5. 远端写入前优先使用 `-DryRun` 或 `validateReplaceTracks`。
6. 禁止使用 `ncm-cli play/pause/resume/stop/next/prev/seek/volume`；播放控制只使用 Orpheus 协议。
7. `searchSong` 返回的 `originalId` 用于播放；歌单编辑使用 `encryptedId`。

## 统一入口

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 `
  -Action status `
  -Json -CompressJson
```

常用动作：

```text
help / diagnose / status / repair / pruneMissing / searchSong / playSong
verifyPlayback / playDefault / setTheme / validateReplaceTracks / replaceTracks
playTheme / dryRun
```

搜索并返回紧凑结果：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 `
  -Action searchSong `
  -Keyword "Eclipse Aimer" `
  -ExactTitle "Eclipse" `
  -Artist "Aimer" `
  -Limit 1 `
  -Json -CompressJson
```

真实播放并验证：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 `
  -Action playSong `
  -OriginalId "2694779693" `
  -ExpectedTitle "Eclipse" `
  -ExpectedArtist "Aimer" `
  -Verify `
  -Json -CompressJson
```

主题歌单写入前预览：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 `
  -Action playTheme `
  -Theme "Aimer精选" `
  -Description "Eclipse - Aimer / 塞壬唱片-MSR。" `
  -SongIds "C9E8705B7783589DB2A3A80CADA71216" `
  -DryRun `
  -Json -CompressJson
```

## 返回语义

- `LOGIN_REQUIRED`：登录未确认；停止联网和远端路径。
- `DRY_RUN`、`URL_PREVIEWED`：仅预览，未写入或未启动客户端。
- `URL_LAUNCHED`：已尝试发起协议 URL，未证明播放状态。
- `VERIFIED`：SMTC 确认标题、歌手和 `Playing` 同时匹配。
- `NOT_VERIFIED`：在重试期限内无法证明目标正在播放。

详见 [docs/json-contract.md](docs/json-contract.md)。

## 项目结构

```text
ncm-bridge/
├── SKILL.md
├── docs/
│   ├── json-contract.md
│   ├── playlist-workflow.md
│   ├── setup.md
│   └── troubleshooting.md
└── scripts/
    ├── OrpheusControl.ps1          # 本地协议播控
    ├── Read-NeteaseSmtc.ps1        # Windows SMTC 状态读取
    ├── entry/                      # Agent 统一入口
    ├── modules/                    # ncm-cli、配置、诊断、播放、歌单模块
    ├── workflows/                  # 歌单初始化、状态、修复与主题工作流
    ├── protocol/                   # Orpheus 命令注册表
    └── tests/                      # 离线、联网和 payload 测试
```

`.ncm-bridge.json` 保存本机歌单绑定，不提交仓库。一个 `PlaylistKey` 对应一个程序专用歌单；其原始 ID 用于播放，加密 ID 用于歌单管理。

## 测试

快速测试不联网、不写远端、不播放、不读取 SMTC：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\tests\test-invoke-fast.ps1
```

完整自检默认只执行 fast。登录成功后可运行联网测试；真实播放必须显式开启：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\tests\test-ncm-bridge.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\tests\test-ncm-bridge.ps1 -Live
powershell -ExecutionPolicy Bypass -File .\scripts\tests\test-invoke-live.ps1 -IncludePlayback
```

仅验证协议 payload：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\tests\test-orpheus-payload.ps1
```

## 参考

- 安装与登录：[docs/setup.md](docs/setup.md)
- 程序专用歌单：[docs/playlist-workflow.md](docs/playlist-workflow.md)
- 故障排查：[docs/troubleshooting.md](docs/troubleshooting.md)
