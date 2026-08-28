---
name: ncm-bridge
description: 使用 ncm-bridge 操作网易云音乐。用于歌曲、歌单的搜索及播放，管理程序专用歌单，最后验证播放结果。
---

# ncm-bridge

`ncm-cli` 负责搜索和歌单管理；`orpheus://` 只负责向本地客户端发起控制请求；Windows SMTC 是唯一的播放验证来源。

## 使用文档

执行任务时，根据场景先读取对应文档。以下文档是本 Skill 的组成部分，不在此重复其详细内容：

- 安装、升级、API Key 与登录：[`docs/setup.md`](docs/setup.md)
- 程序专用歌单的状态、修复与写入：[`docs/playlist-workflow.md`](docs/playlist-workflow.md)
- JSON 字段、状态码与播放验证语义：[`docs/json-contract.md`](docs/json-contract.md)
- 登录、Orpheus 和 SMTC 问题：[`docs/troubleshooting.md`](docs/troubleshooting.md)

## 首次登录门控

- 仅支持 Windows、PowerShell 5+ 和 Node.js >= 18。
- 每次使用本 Skill 时，先执行以下脚本，并解析 JSON：

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\workflows\start-ncm-cli-login.ps1 -Json -CompressJson
  ```

- `code: OK`：已登录，可以继续任务。
- `code: LOGIN_WINDOW_STARTED`：可见扫码窗口已经启动。停止当前自动化，等待用户扫码并明确确认完成；确认后重新执行此脚本。
- 脚本非零退出、没有 JSON 或返回非上述代码：只运行 [`scripts/tests/test-preflight.ps1`](scripts/tests/test-preflight.ps1)，向 Agent 上报 `AffectedComponents` 与失败详情；然后按 [`docs/setup.md`](docs/setup.md) 修复环境并重新执行登录脚本。
- `appId` 与 `privateKey` 由用户单独提供和配置。仅当 preflight 表明安装环境存在问题时，才使用 [`scripts/workflows/install-ncm-cli.ps1`](scripts/workflows/install-ncm-cli.ps1)；默认保留已安装版本，升级必须显式传入 `-Upgrade`。
- 未登录时，禁止搜索、歌单、SMTC、远端写入和播放。不要根据缺失命令、`unknown command` 或 `--help` 判断版本或功能缺失。

## 执行顺序

1. 完成首次登录门控后，按任务调用统一入口 [`scripts/entry/invoke-ncm-bridge.ps1`](scripts/entry/invoke-ncm-bridge.ps1)，固定优先使用 `-Json -CompressJson`。
2. 不运行 `-Action help`、`ncm-cli --help` 或 `ncm-cli commands` 来发现功能；以下动作目录是完整且确定的调用契约。
3. 写入远端歌单前先使用 `-DryRun` 或 `validateReplaceTracks`。具体歌单流程见 [`docs/playlist-workflow.md`](docs/playlist-workflow.md)。
4. 发起播放后，只有 SMTC 验证成功才可报告播放成功。状态码解释见 [`docs/json-contract.md`](docs/json-contract.md)。
5. 操作失败时才调用对应层级的自检；不要一次性调用所有测试。

## 统一入口

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 `
  -Action status `
  -Json -CompressJson
```

除非调用模板另有说明，所有动作都追加 `-Json -CompressJson`。`PlaylistKey` 缺省时使用配置中的活动歌单；`ConfigPath` 仅在用户指定另一份本地绑定文件时传入。不要自行补造歌曲 ID、歌单 ID、主题或验证期望值。

### 动作目录

| 任务 | Action 与必填参数 | 副作用与结果 |
|---|---|---|
| 诊断环境 | `diagnose`；可选 `-Verify` | 只读；检查 ncm-cli、登录、配置和可选 SMTC。 |
| 查看歌单状态 | `status`；可选 `-PlaylistKey`、`-ConfigPath` | 只读。 |
| 修复本地绑定 | `repair` 或 `pruneMissing`；可选 `-DryRun` | 只修改本地 `.ncm-bridge.json`。 |
| 搜索歌曲 | `searchSong -Keyword <关键词>`；可选 `-ExactTitle`、`-Artist`、`-Limit` | 只读；返回 `originalId` 和 `encryptedId`。 |
| 播放单曲 | `playSong -OriginalId <原始歌曲ID>`；验证时附加 `-ExpectedTitle`、`-ExpectedArtist`、`-Verify` | 会启动 Orpheus；只有 `VERIFIED` 才算成功。 |
| 验证当前播放 | `verifyPlayback -ExpectedTitle <标题> -ExpectedArtist <歌手>` | 只读 SMTC。 |
| 播放当前专用歌单 | `playDefault`；可选 `-PlaylistKey`、`-DryRun` | 会启动 Orpheus；不自动验证。 |
| 设置歌单主题 | `setTheme -Theme <主题>`；可选 `-Description`、`-DryRun` | 远端写入；先 dry-run。 |
| 验证或替换曲目 | `validateReplaceTracks` 或 `replaceTracks -SongIds <加密歌曲ID列表>` | 前者只读；后者远端写入，先 `-DryRun`。 |
| 设置、替换并播放主题歌单 | `playTheme -Theme <主题> -SongIds <加密歌曲ID列表>`；验证时附加期望信息与 `-Verify` | 写入并播放；先 `-DryRun`。 |
| 生成协议 payload | `dryRun` | 仅兼容动作，不启动客户端。 |

`originalId` 只用于 `playSong`，`encryptedId` 只用于歌单编辑。所有动作的字段与代码语义以 [`docs/json-contract.md`](docs/json-contract.md) 为准。

### Orpheus 本地播控命令

完整注册表见 [`scripts/protocol/orpheus_commands.json`](scripts/protocol/orpheus_commands.json)。这些是通过 `OrpheusControl.ps1` 发给已安装网易云音乐客户端的本地协议命令，不是 `ncm-cli` 子命令；需要播控时应使用下表中的注册名称：

| 注册名称 | 作用 | 参数 |
|---|---|---|
| `next` / `previous` | 下一首 / 上一首 | 无 |
| `pause` / `resume` | 暂停 / 继续 | 无 |
| `mode_random` / `mode_order` / `mode_single` / `mode_cycle` | 随机 / 顺序 / 单曲循环 / 列表循环 | 无 |
| `set_volume` | 设置音量 | `value`：整数 `0-100` |
| `seek` | 跳转进度 | `value`：不小于 `0` 的秒数，可带小数 |
| `play_song` | 播放歌曲 | `id`：歌曲 `originalId` |
| `play_playlist` | 播放歌单 | `id`：歌单数字原始 ID |

目前统一入口已封装 `play_song` 和 `play_playlist`（对应 `playSong`、`playDefault`、`playTheme`）。其余本地控制命令直接调用以下脚本；执行前仍须完成登录门控，且只有 SMTC 能验证播放状态：

```powershell
# 示例：暂停、继续、切换下一首
. .\scripts\OrpheusControl.ps1
Invoke-OrpheusCommand -Name pause
Invoke-OrpheusCommand -Name resume
Invoke-OrpheusCommand -Name next

# 示例：设置音量和跳转进度；先用 -DryRun 检查 payload
Invoke-OrpheusCommand -Name set_volume -Params @{ value = 50 } -DryRun
Invoke-OrpheusCommand -Name seek -Params @{ value = 86.5 } -DryRun
```

未通过统一入口 `-Verify` 或 `verifyPlayback` 取得 SMTC 确认时，只能报告协议已发起（`URL_LAUNCHED`）；`-DryRun` 只能报告 payload 预览，不能报告客户端已执行。

### 标准调用模板

以下模板是唯一需要使用的入口形式。先完成登录门控，再按用户明确的目标选择一项；不以 `help` 或命令行帮助作补充探测。

```powershell
# 只读诊断与状态
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action diagnose -Json -CompressJson
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action status -Json -CompressJson

# 本地绑定修复：先预览，再在用户同意后去掉 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action repair -DryRun -Json -CompressJson
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action pruneMissing -DryRun -Json -CompressJson

# 搜索：从 records 中取 originalId 用于播放、encryptedId 用于歌单编辑
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action searchSong -Keyword "歌曲名 歌手" -ExactTitle "歌曲名" -Artist "歌手" -Limit 5 -Json -CompressJson

# 播放和验证：只有用户明确要求播放时才调用；-Verify 时必须同时给出标题和歌手
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action playSong -OriginalId "原始歌曲ID" -ExpectedTitle "歌曲名" -ExpectedArtist "歌手" -Verify -Json -CompressJson
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action verifyPlayback -ExpectedTitle "歌曲名" -ExpectedArtist "歌手" -Json -CompressJson
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action playDefault -Json -CompressJson

# 歌单写入：先验证或预览；得到用户确认后，才运行不带 -DryRun 的写入命令
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action validateReplaceTracks -SongIds "加密歌曲ID1,加密歌曲ID2" -Json -CompressJson
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action replaceTracks -SongIds "加密歌曲ID1,加密歌曲ID2" -DryRun -Json -CompressJson
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action setTheme -Theme "主题" -Description "描述" -DryRun -Json -CompressJson
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action playTheme -Theme "主题" -SongIds "加密歌曲ID1,加密歌曲ID2" -DryRun -Json -CompressJson

# 协议 payload 预览（不联网、不播放）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\entry\invoke-ncm-bridge.ps1 -Action dryRun -Json -CompressJson
```

### 结果处理

- `OK`：动作完成；继续任务。
- `LOGIN_REQUIRED`：停止联网动作；回到首次登录门控。
- `MISSING`：读取 [`docs/playlist-workflow.md`](docs/playlist-workflow.md)，执行状态修复或初始化流程。
- `DRY_RUN`、`URL_PREVIEWED`：仅预览，不报告远端写入或播放完成。
- `URL_LAUNCHED`：仅表示已尝试启动协议 URL；需要 `verifyPlayback` 才能确认播放。
- `VERIFIED`：SMTC 已确认目标播放。
- `NOT_VERIFIED`：读取 `verification.diagnostics` 或 `diagnostics`，再按 [`docs/troubleshooting.md`](docs/troubleshooting.md) 排查。

## 强约束

- 禁止使用 `ncm-cli play/pause/resume/stop/next/prev/seek/volume`。
- `orpheus://` URL 已生成或已启动，不代表客户端已经播放。
- dry-run 只验证 payload 或写入计划，不验证客户端执行。
- 只有 SMTC 同时确认期望标题、歌手和 `Playing` 状态时，结果才是 `VERIFIED`。
- `NOT_VERIFIED` 时读取 `verification.diagnostics` 或 `diagnostics`，并按 [`docs/troubleshooting.md`](docs/troubleshooting.md) 排查。

## 失败后的自检

```powershell
# 环境、脚本、Orpheus 协议注册与 payload 失败
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tests\test-preflight.ps1 -Json

# 登录、搜索、状态或 SMTC 只读路径失败
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tests\test-online.ps1 -Json

# 仅在用户允许再次真实播放后调用
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tests\test-playback.ps1 -Json

# 歌单写入失败：默认只验证与 dry-run；真实写入必须显式 -Apply
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tests\test-playlist-write.ps1 -SongIds "加密歌曲ID1,加密歌曲ID2" -Json
```

每个报告包含 `Layer`、`Summary`、`Results` 与 `AffectedComponents`；将失败组件和详情上报给 Agent，再按 [`docs/troubleshooting.md`](docs/troubleshooting.md) 处理。总入口 [`scripts/tests/test-ncm-bridge.ps1`](scripts/tests/test-ncm-bridge.ps1) 默认只运行 preflight，其他层必须显式开启。
