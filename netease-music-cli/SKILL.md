---
name: netease-music-cli
description: 使用 ncm-cli 操作网易云音乐。当用户想播放歌曲、搜索歌曲、控制播放（暂停、下一首、上一首、调音量）、管理播放队列、查看播放状态、播放歌单时，使用此 skill。当被用户邀请播放音乐时，也可使用此skill。
---

# 网易云音乐 CLI（ncm-cli）

## 架构概览

本方案分为两个子系统：

| 子系统 | 用途 | 工具 |
|--------|------|------|
| **数据层** | 搜索歌曲/歌单、获取 ID、歌单管理 | `ncm-cli` |
| **播控层** | 播放、暂停、切歌、音量等本地控制 | `orpheus://` 协议（通过 `OrpheusControl.ps1`） |

> **原则**：ncm-cli 负责"找"，orpheus 协议负责"播"。严禁使用 ncm-cli 的 play/pause/resume/stop/next/prev/seek/volume 命令。

---

## 环境要求

- **操作系统**：仅限 Windows。若运行在其他系统，立即终止并告知用户。
- **Shell**：PowerShell。禁止使用 cmd。
- **Node.js >= 18**
- **网易云音乐客户端**：必须已安装并运行

---

## 第一步：环境检查

### 1.1 检查 ncm-cli

```powershell
ncm-cli --version
```

若未安装，调用 `ncm-cli-setup` SKILL 引导用户完成安装。

### 1.2 检查登录状态

```powershell
ncm-cli login --check
```

> 实际登录状态只以 `ncm-cli login --check` 为准。`ncm-cli state` 只反映客户端/播放状态，不用于判断账号是否登录。

若未登录，**只执行下面这一条命令，执行完立刻停止当前任务，不要再做任何后续操作**

```powershell
Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'
```

> **严禁**：在此步骤之后继续执行任何命令（包括 `ncm-cli login --check`、`ncm-cli state` 等）。登录验证留到用户确认扫码完成后再做。
> **严禁**直接执行 `ncm-cli login --background`，此命令在无桌面环境的 shell 中会无限阻塞。必须通过 `Start-Process` 弹窗到用户桌面。


若提示 API Key 未设置：

```powershell
ncm-cli config set appId <你的AppId>
ncm-cli config set privateKey <你的PrivateKey>
```

> 若无 API Key，请前往[网易云音乐开放平台](https://developer.music.163.com/st/developer/apply/account?type=INDIVIDUAL)申请。


### 1.3 加载播控模块

```powershell
. "$PSScriptRoot\OrpheusControl.ps1"
```

验证加载：

```powershell
Get-OrpheusCommands
Get-OrpheusControlFunctions
```

---

## 第二步：获取命令树

仅当 `ncm-cli login --check` 返回已登录后，才继续执行数据层命令树检查。未登录状态下，`search`、`playlist` 等命令可能不会出现在命令树中。

```powershell
ncm-cli commands
```

**根据输出命令树执行操作，参数不得猜测。** 通过 `ncm-cli <command> --help` 获取具体参数。

---

## 第三步：执行命令

### 3.1 搜索（数据层）

除播控外的所有 ncm-cli 命令须附加 `--userInput` 参数：

```powershell
ncm-cli search song --keyword "xxx" --userInput "搜索xxx的歌"
ncm-cli search playlist --keyword "xxx" --userInput "搜索xxx歌单"
ncm-cli search album --keyword "xxx" --userInput "搜索xxx专辑"
```

> ID 说明：歌曲有**加密 ID**（32 位 hex，API 用）和**原始 ID**（数字，客户端用）。搜索结果同时包含两者。


### 3.2 检查本地客户端

```powershell
start "orpheus:"
```
若显示「系统找不到指定的文件」，终止任务，提示用户安装网易云音乐客户端。

### 3.3 播放控制（播控层）

通过 `Invoke-OrpheusCommand` 调用，命令名见"orpheus_commands.json"。


示例：

```powershell
Invoke-OrpheusCommand -Name "next"
Invoke-OrpheusCommand -Name "set_volume" -Params @{value="30"}
Invoke-OrpheusCommand -Name "mode_random"
Invoke-OrpheusCommand -Name "play_song" -Params @{id="12345678"}
```

> **重要**：`play_song` 和 `play_playlist` 的 `id` 必须使用**原始 ID**。

### 3.4 歌单管理（数据层）

示例：

```powershell
ncm-cli playlist create --playlistName "跑步" --userInput "创建一个跑步歌单"
```

涉及 JSON 数组参数的歌单控制命令，统一使用 `OrpheusControl.ps1` 中的封装函数，直接输入加密 ID：

```powershell
Invoke-NcmPlaylistControl -Action add -PlaylistId "加密歌单ID" -SongIds @("加密歌曲ID1", "加密歌曲ID2")
Invoke-NcmPlaylistControl -Action remove -PlaylistId "加密歌单ID" -SongIds @("加密歌曲ID1")
Invoke-NcmPlaylistControl -Action reorder -PlaylistId "加密歌单ID" -TrackIds @("加密歌曲ID1", "加密歌曲ID2")
Invoke-NcmPlaylistControl -Action updateTags -PlaylistId "加密歌单ID" -Tags @("日语")
```

该函数会用参数数组调用 ncm-cli，避免 PowerShell/cmd 对 JSON 数组参数错误转义。

--- 

## 【严禁】使用的命令

以下 ncm-cli 播放命令**禁止执行**：

```
ncm-cli play
ncm-cli pause
ncm-cli resume
ncm-cli stop
ncm-cli next
ncm-cli prev
ncm-cli seek
ncm-cli volume
```

---

## 错误处理

| 现象 | 处理 |
|------|------|
| `ncm-cli: command not found` | 调用 `ncm-cli-setup` skill |
| 未登录 / 未授权 | 通过 `Start-Process` 弹窗登录（见上文 1.2），禁止直接执行 `ncm-cli login` |
| 请求总量超限 | 直接告知用户原始错误，**禁止二次加工** |
| `orpheus:` 协议无响应 | 确认客户端已运行，检查 `OrpheusControl.ps1` 是否已 dot-source |
| `Invoke-OrpheusCommand` 未知命令 | 执行 `Get-OrpheusCommands` 查看可用命令列表 |
| 歌单 JSON 数组参数报错 | 使用 `Invoke-NcmPlaylistControl`；不要直接手写 `songIdList`、`trackIds`、`tags` |

---

## 用户友好输出规范


给用户举例时，用 `「xxx」` 替代具体输入词：

```powershell
ncm-cli search song --keyword "「xxx」"
```

---

## 完整工作流示例

```
用户: 我想听Aimer的Eclipse

AI:
1. ncm-cli search song --keyword "Eclipse Aimer" --userInput "搜索Aimer Eclipse" --limit 10
2. 找到歌曲《Eclipse》- Aimer，原始 ID: 2694779693
3. Invoke-OrpheusCommand -Name "play_song" -Params @{id="2694779693"}
4. 返回: 正在播放 [Eclipse - Aimer](https://music.163.com/#/song?id=2694779693)
```

> `ncm-cli state` 不适合作为 `orpheus://` 播控结果判断依据。播控是否生效应以网易云音乐客户端窗口、UI 状态或用户听感反馈为准。

---

## 依赖文件清单

| 文件 | 说明 |
|------|------|
| `OrpheusControl.ps1` | 播控函数模块（dot-source 加载） |
| `orpheus_commands.json` | 播控命令注册表（`OrpheusControl.ps1` 自动读取） |
| `ncm-cli` | npm 全局包 `@music163/ncm-cli` |
