# CHANGELOG

## Unreleased

### 新增

- 新增 Agent 统一入口 `scripts/invoke-ncm-bridge.ps1`，集中处理状态、修复、搜索、播放、主题歌单、预检和 SMTC 验证。
- 新增小模块拆分：
  - `scripts/NcmBridge.Cli.ps1`
  - `scripts/NcmBridge.Config.ps1`
  - `scripts/NcmBridge.Playlist.ps1`
  - `scripts/NcmBridge.Text.ps1`
- 新增程序专用歌单工作流脚本：
  - `init-ncm-bridge-playlist.ps1`
  - `get-ncm-bridge-status.ps1`
  - `repair-ncm-bridge-config.ps1`
  - `set-ncm-bridge-theme.ps1`
  - `replace-ncm-bridge-tracks.ps1`
  - `play-ncm-bridge-theme.ps1`
- 新增 `searchSong` 紧凑搜索输出，支持 `ExactTitle` 和 `Artist` 筛选，减少 Agent 解析大 JSON 的成本。
- 新增 `playSong -Verify`、`playTheme -Verify` 和 `verifyPlayback`，播放结果只通过 SMTC 验证。
- 新增 `-CompressJson`，用于 Agent 高密度 JSON 输出。
- 新增远端写入预览：
  - `setTheme -DryRun`
  - `replaceTracks -DryRun`
  - `playTheme -DryRun`
- 新增 `pruneMissing` 入口，用于预览或清理失效的本地歌单 key。
- 新增 `test-invoke-ncm-bridge.ps1` 和 `test-orpheus-payload.ps1`。
- 新增低频参考文档：
  - `netease-music-cli/references/setup.md`
  - `netease-music-cli/references/playlist-workflow.md`
  - `netease-music-cli/references/troubleshooting.md`
  - `netease-music-cli/references/json-contract.md`

### 变更

- `netease-music-cli/SKILL.md` 重构为 Agent 必读最小规则，默认推荐 `invoke-ncm-bridge.ps1`。
- `README.md` 重构为人类维护文档，保留架构、快速开始、统一入口、测试和治理原则。
- `OrpheusControl.ps1` 收缩为纯播控/SMTC 状态模块，不再混入 ncm-cli 数据层逻辑。
- `Read-NeteaseSmtc.ps1` 增加 `Attempts`、`RetryDelayMs`、`InitialDelayMs`，适配不同电脑上的 SMTC 同步延迟。
- `verifyPlayback` 改为目标匹配轮询：只有标题、歌手和 `Playing` 同时匹配，才返回 `VERIFIED`。
- `test-ncm-bridge.ps1` 纳入新增模块和入口脚本的完整性与语法检查。
- `test-orpheus-dryrun.ps1` 保留兼容；推荐使用 `test-orpheus-payload.ps1` 表达 payload 测试语义。

### 修复

- 修复 `activePlaylistKey` 指向已删除歌单时需要人工判断的问题，支持通过 `repair` 自动回到健康 key。
- 修复 SMTC 验证过早读取导致误判的问题，播放验证现在会等待目标状态出现。
- 修复 dot-source `Read-NeteaseSmtc.ps1` 时同名参数污染入口验证参数的问题。
- 修复 `test-orpheus-payload.ps1` 转发 switch 参数时的 PowerShell 参数转换问题。

### 约束

- `orpheus://` URL 发出、payload dry-run 或进程返回成功，都不代表客户端已经播放。
- 播放结果只能通过 SMTC 验证。
- 禁止使用 `ncm-cli play/pause/resume/stop/next/prev/seek/volume`。
- `.ncm-bridge.json` 和 `.tmp-ncm-bridge-config.json` 是本地状态，继续被 `.gitignore` 忽略。

### 验证

- `scripts/test-ncm-bridge.ps1`：`9/9 passed`
- `scripts/test-invoke-ncm-bridge.ps1`：`7/7 passed`
- `scripts/test-orpheus-payload.ps1`：`4/4 passed`
- `playSong -Verify`：SMTC 验证 `Eclipse - Aimer` 成功
- `playTheme -Verify`：SMTC 验证 `Eclipse - Aimer` 成功
