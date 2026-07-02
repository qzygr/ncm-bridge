# ncm-bridge

网易云音乐 Agent 桥接项目。目标是在完成搜索、歌单管理和本地播放控制的同时，尽量降低 Agent token 消耗，并避免神文件和神函数。

## 核心原则

- Agent 默认只走 `scripts/invoke-ncm-bridge.ps1`。
- `ncm-cli` 负责搜索和歌单管理。
- `orpheus://` 只负责发起本地客户端协议 URL。
- `orpheus://` URL 发出、payload dry-run 或进程返回成功，都不代表客户端已经播放。
- 播放结果只能通过 Windows SMTC 验证；入口脚本会轮询 SMTC，直到目标曲目匹配或超时。
- 真实远端写入前优先使用 `-DryRun` / `validateReplaceTracks`。

## 架构

| 层 | 职责 | 文件 |
|---|---|---|
| Agent 入口 | 常用动作分发、短 JSON 输出 | `scripts/invoke-ncm-bridge.ps1` |
| 数据层 | ncm-cli JSON 调用、歌单查询和修改 | `scripts/NcmBridge.*.ps1` |
| 播控层 | 启动 `orpheus://` URL | `netease-music-cli/OrpheusControl.ps1` |
| 状态层 | 读取 SMTC 并支持延时/重试 | `netease-music-cli/Read-NeteaseSmtc.ps1` |
| Skill | Agent 必读最小规则 | `netease-music-cli/SKILL.md` |
| 细节文档 | 低频说明，减少默认读取量 | `netease-music-cli/references/` |

## 环境要求

- Windows
- PowerShell 5+
- Node.js >= 18
- 网易云音乐客户端
- `@music163/ncm-cli`
- 网易云音乐开放平台 API Key

## 快速开始

安装：

```powershell
npm install -g @music163/ncm-cli
ncm-cli config set appId <AppId>
ncm-cli config set privateKey <PrivateKey>
```

登录：

```powershell
Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'
```

自检：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-ncm-bridge.ps1
```

如果自检只有 `account login status` 失败，只启动登录窗口并停止，等扫码完成后重新自检。

## 统一入口

查看状态：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action status -Json -CompressJson
```

搜索歌曲：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 `
  -Action searchSong `
  -Keyword "Eclipse Aimer" `
  -ExactTitle "Eclipse" `
  -Artist "Aimer" `
  -Limit 1 `
  -Json -CompressJson
```

播放并用 SMTC 验证：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 `
  -Action playSong `
  -OriginalId "2694779693" `
  -ExpectedTitle "Eclipse" `
  -ExpectedArtist "Aimer" `
  -Verify `
  -Json -CompressJson
```

主题歌单预览：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 `
  -Action playTheme `
  -Theme "Aimer精选" `
  -Description "Eclipse - Aimer / 塞壬唱片-MSR。" `
  -SongIds "C9E8705B7783589DB2A3A80CADA71216" `
  -DryRun `
  -Json -CompressJson
```

主题歌单播放并验证：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 `
  -Action playTheme `
  -Theme "Aimer精选" `
  -Description "Eclipse - Aimer / 塞壬唱片-MSR。" `
  -SongIds "C9E8705B7783589DB2A3A80CADA71216" `
  -ExpectedTitle "Eclipse" `
  -ExpectedArtist "Aimer" `
  -Verify `
  -Json -CompressJson
```

## 常用动作

| Action | 用途 |
|---|---|
| `status` | 读取当前专用歌单健康状态 |
| `repair` | 修复 active key 指向失效歌单的问题 |
| `pruneMissing` | 清理失效 key，建议先加 `-DryRun` |
| `searchSong` | 返回紧凑歌曲搜索结果 |
| `playSong` | 播放原始数字歌曲 ID，可加 `-Verify` |
| `verifyPlayback` | 只通过 SMTC 验证当前播放 |
| `setTheme` | 设置专用歌单主题，可加 `-DryRun` |
| `validateReplaceTracks` | 预检替换曲目 |
| `replaceTracks` | 替换专用歌单曲目，可加 `-DryRun` 只预检 |
| `playTheme` | 设置主题、替换曲目并播放，可加 `-Verify` |
| `dryRun` | 兼容入口，验证 orpheus payload 生成 |

## 测试

完整自检：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-ncm-bridge.ps1
```

入口测试：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-invoke-ncm-bridge.ps1
```

payload 测试：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-orpheus-payload.ps1
```

`test-orpheus-dryrun.ps1` 保留为兼容入口。payload 测试不验证客户端是否执行。

## 文件结构

```text
ncm-bridge/
├── ncm-cli-setup/
│   └── SKILL.md
├── netease-music-cli/
│   ├── SKILL.md
│   ├── OrpheusControl.ps1
│   ├── Read-NeteaseSmtc.ps1
│   ├── orpheus_commands.json
│   └── references/
├── scripts/
│   ├── NcmBridge.Cli.ps1
│   ├── NcmBridge.Config.ps1
│   ├── NcmBridge.Playlist.ps1
│   ├── NcmBridge.Text.ps1
│   ├── invoke-ncm-bridge.ps1
│   ├── test-ncm-bridge.ps1
│   ├── test-invoke-ncm-bridge.ps1
│   └── test-orpheus-payload.ps1
└── README.md
```

## 本地配置

`.ncm-bridge.json` 保存专用歌单绑定，包含原始歌单 ID 和加密歌单 ID。它是本地状态，不提交仓库。

`.gitignore` 已忽略：

```text
.ncm-bridge.json
.tmp-ncm-bridge-config.json
.codex-tmp/
.codex-cache/
```

## 禁用命令

禁止用 `ncm-cli` 的播放控制命令：

```text
ncm-cli play
ncm-cli pause
ncm-cli resume
ncm-cli stop
ncm-cli next
ncm-cli prev
ncm-cli seek
ncm-cli volume
```

## 更多细节

- 安装登录：`netease-music-cli/references/setup.md`
- 歌单工作流：`netease-music-cli/references/playlist-workflow.md`
- 排障：`netease-music-cli/references/troubleshooting.md`
- JSON 契约：`netease-music-cli/references/json-contract.md`
