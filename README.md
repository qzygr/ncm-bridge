# NCM Bridge

> 让自动化脚本和 AI 助手可靠地操作本地网易云音乐。

## 简介

**NCM Bridge** 是一个面向 Windows 的 PowerShell 工具集，为 `ncm-cli` 和本地网易云音乐客户端提供一层稳定的桥接能力。

它可以完成歌曲搜索、歌单管理和本地播放控制。播放请求通过网易云音乐支持的 `orpheus://` 协议发送给客户端，播放结果则通过 Windows SMTC 读取并验证。

项目不模拟鼠标键盘，不依赖图像识别，也不修改客户端内存。

> 当前仅支持 Windows。macOS 和 Linux 不在项目支持范围内。

## 功能特性

| 功能 | 支持状态 | 说明 |
|---|---|---|
| 搜索歌曲 | 支持 | 使用 `ncm-cli` 搜索并返回歌曲信息及两类 ID |
| 播放歌曲 | 支持 | 使用歌曲 `originalId` 通过 Orpheus 发起播放 |
| 播放歌单 | 支持 | 播放已绑定的程序专用歌单 |
| 暂停 / 继续 | 支持 | Orpheus `pause` / `resume` 命令 |
| 上一首 / 下一首 | 支持 | Orpheus `previous` / `next` 命令 |
| 播放模式 | 支持 | 随机、顺序、单曲循环和列表循环 |
| 音量 / 进度 | 支持 | 设置绝对音量 `0-100`，或跳转到指定秒数 |
| 程序专用歌单 | 支持 | 创建、绑定、查看状态、设置主题和替换曲目 |
| 播放验证 | 支持 | 通过 SMTC 验证标题、歌手和 `Playing` 状态 |
| 收藏当前歌曲 | 不提供 | 当前协议和脚本没有实现收藏动作 |
| 音效控制 | 不提供 | 当前项目不控制网易云客户端音效设置 |

## 工作原理

NCM Bridge 将功能分为三层：

1. `ncm-cli`：负责登录、远端搜索、歌单查询和歌单编辑。
2. `orpheus://`：负责向本机网易云音乐客户端发起播放和控制请求。
3. Windows SMTC：负责读取当前媒体会话，作为播放验证来源。

协议 URL 已成功启动，只能说明客户端调用路径已被触发，不能证明歌曲已经播放。只有 SMTC 同时确认目标标题、歌手和 `Playing` 状态时，才算验证成功。

## 快速开始

### 环境要求

- Windows 10 或 Windows 11
- PowerShell 5.1 或更高版本
- Node.js 18 或更高版本
- 已安装网易云音乐 Windows 客户端
- 网易云音乐开放平台的 `appId` 和 `privateKey`

### 安装

```powershell
git clone https://github.com/qzygr/ncm-bridge.git
Set-Location .\ncm-bridge
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\workflows\install-ncm-cli.ps1 -Json
```

仓库clone完毕后，应提示Agent安装该SKILL，这应该会很容易（XD
安装脚本只在缺少 `ncm-cli` 时安装，默认不会升级已有版本。需要升级时显式添加 `-Upgrade`；只查看安装计划时使用 `-DryRun`。

### 配置 API Key

从[网易云音乐开放平台](https://developer.music.163.com/st/developer/apply/account?type=INDIVIDUAL)获取凭据后执行：

```powershell
ncm-cli config set appId <你的AppId>
ncm-cli config set privateKey <你的PrivateKey>
```

API Key 由 `ncm-cli` 管理，不会写入本项目的配置文件或日志。

### 登录

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\workflows\start-ncm-cli-login.ps1 -Json
ncm-cli login --check
```

如果尚未登录，脚本会打开可见的扫码窗口。扫码完成后再次运行 `ncm-cli login --check`。

## 常用操作

统一入口位于 `scripts/entry/invoke-ncm-bridge.ps1`。添加 `-Json` 可获得结构化结果，添加 `-CompressJson` 可压缩为单行。

### 搜索歌曲

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 `
  -Action searchSong -Keyword "Eclipse Aimer" -ExactTitle "Eclipse" -Artist "Aimer" -Limit 1 `
  -Json -CompressJson
```

搜索结果中的 `originalId` 用于播放，`encryptedId` 用于歌单编辑。

### 播放并验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 `
  -Action playSong -OriginalId <originalId> `
  -ExpectedTitle <歌曲名> -ExpectedArtist <歌手> -Verify `
  -Json -CompressJson
```

返回 `code: VERIFIED` 才表示播放已被 SMTC 确认。

### 查看和修复歌单

```powershell
# 查看当前程序专用歌单
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action status -Json

# 修复前先预览
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action repair -DryRun -Json
```

### 替换歌单曲目

`SongIds` 必须使用搜索结果中的 `encryptedId`。真实写入前建议先验证和预览：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 `
  -Action validateReplaceTracks -SongIds "<encryptedId1>,<encryptedId2>" -Json

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 `
  -Action replaceTracks -SongIds "<encryptedId1>,<encryptedId2>" -DryRun -Json
```

确认曲目后，去掉 `-DryRun` 才会执行远端替换。

### 直接使用 Orpheus

完整命令表见 [`scripts/protocol/orpheus_commands.json`](scripts/protocol/orpheus_commands.json)：

```powershell
. .\scripts\OrpheusControl.ps1
Invoke-OrpheusCommand -Name pause
Invoke-OrpheusCommand -Name resume
Invoke-OrpheusCommand -Name next
Invoke-OrpheusCommand -Name set_volume -Params @{ value = 50 }
Invoke-OrpheusCommand -Name seek -Params @{ value = 86.5 }
```

添加 `-DryRun` 可以只生成协议 URL，不启动客户端。

## 测试

项目按副作用拆分测试层级：

```powershell
# 环境、脚本、模块、协议和 payload
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tests\test-preflight.ps1 -Json

# 登录、搜索、状态和 SMTC 只读路径
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tests\test-online.ps1 -Json

# 一次真实播放并验证 SMTC
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tests\test-playback.ps1 -Json

# 歌单验证和 dry-run；真实写入需显式添加 -Apply
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tests\test-playlist-write.ps1 `
  -SongIds "<encryptedId1>,<encryptedId2>" -Json
```

总测试入口默认只运行前置测试；完整测试需要显式开启对应层级：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tests\test-ncm-bridge.ps1 `
  -Online -Playback -PlaylistWrite -PlaylistSongIds "<encryptedId1>,<encryptedId2>" -Json
```

## 项目结构

```text
ncm-bridge/
├── SKILL.md                         # Agent 使用规范
├── docs/                            # 安装、歌单、JSON 和故障排查文档
├── scripts/
│   ├── entry/                       # 统一入口
│   ├── modules/                     # CLI、配置、歌单、播放和诊断模块
│   ├── protocol/                    # Orpheus 命令注册表
│   ├── workflows/                   # 安装、登录和歌单工作流
│   └── tests/                       # 分层测试
├── .ncm-bridge.json                 # 本地歌单绑定，不应提交
└── CHANGELOG.md
```

## 贡献

欢迎提交 Issue 和 Pull Request。提交前请确认：

- 代码和文档路径与当前目录结构一致。
- PowerShell 脚本通过语法检查。
- 涉及播放的改动经过 SMTC 验证。
- 涉及远端歌单的改动先完成 dry-run 和结果校验。

## 开源协议

本项目采用 [MIT License](LICENSE)。

更多细节请阅读 [`docs/setup.md`](docs/setup.md)、[`docs/playlist-workflow.md`](docs/playlist-workflow.md)、[`docs/json-contract.md`](docs/json-contract.md) 和 [`docs/troubleshooting.md`](docs/troubleshooting.md)。
