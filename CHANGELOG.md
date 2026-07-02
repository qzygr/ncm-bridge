# CHANGELOG

## Unreleased

### 新增

- 新增 Agent 统一入口 `scripts/invoke-ncm-bridge.ps1`，集中处理状态、修复、搜索、播放、主题歌单、预检和 SMTC 验证。
- 新增小模块拆分：
  - `scripts/NcmBridge.Cli.ps1`
  - `scripts/NcmBridge.Config.ps1`
  - `scripts/NcmBridge.Help.ps1`
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
- 新增 `help` 动作，输出统一入口动作、关键参数和强约束。
- 新增远端写入预览：
  - `setTheme -DryRun`
  - `replaceTracks -DryRun`
  - `playTheme -DryRun`
- 新增 `pruneMissing` 入口，用于预览或清理失效的本地歌单 key。
- 新增测试分层：
  - `test-invoke-fast.ps1`：离线 fast 层。
  - `test-invoke-live.ps1`：联网、登录、搜索和 SMTC 路径层，真实播放需显式 `-IncludePlayback`。
  - `test-invoke-ncm-bridge.ps1`：兼容入口，转调 fast。
  - `test-orpheus-payload.ps1`：payload 测试入口。
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
- `test-ncm-bridge.ps1` 默认聚合 fast；加 `-Live` 才跑联网搜索和 SMTC 路径，加 `-IncludePlayback` 才真实播放。
- `test-orpheus-dryrun.ps1` 保留兼容；推荐使用 `test-orpheus-payload.ps1` 表达 payload 测试语义。
- `netease-music-cli/references/json-contract.md` 增加 `code` 枚举，明确 `URL_LAUNCHED` 不等于 `VERIFIED`。

### 修复

- 修复 `activePlaylistKey` 指向已删除歌单时需要人工判断的问题，支持通过 `repair` 自动回到健康 key。
- 修复 SMTC 验证过早读取导致误判的问题，播放验证现在会等待目标状态出现。
- 修复 `playSong -Verify` 验证失败时仍可能返回 `URL_LAUNCHED` 的语义问题；现在返回 `NOT_VERIFIED`。
- 修复 dot-source `Read-NeteaseSmtc.ps1` 时同名参数污染入口验证参数的问题。
- 修复 `test-orpheus-payload.ps1` 转发 switch 参数时的 PowerShell 参数转换问题。

### 约束

- `orpheus://` URL 发出、payload dry-run 或进程返回成功，都不代表客户端已经播放。
- 播放结果只能通过 SMTC 验证。
- 禁止使用 `ncm-cli play/pause/resume/stop/next/prev/seek/volume`。
- `.ncm-bridge.json` 和 `.tmp-ncm-bridge-config.json` 是本地状态，继续被 `.gitignore` 忽略。

### 验证

- `scripts/test-invoke-fast.ps1`：`12/12 passed`
- `scripts/test-invoke-ncm-bridge.ps1 -Json`：fast `12/12 passed`
- `scripts/test-ncm-bridge.ps1`：`3/3 passed`
- `scripts/test-invoke-live.ps1`：`5/5 passed`，真实播放路径按设计跳过。
- `scripts/test-invoke-live.ps1 -IncludePlayback`：`5/5 passed`，SMTC 验证 `Eclipse - Aimer` 成功。
- `scripts/test-orpheus-payload.ps1`：`4/4 passed`
- `invoke-ncm-bridge.ps1 -Action help -Json -CompressJson`：帮助契约检查通过。
- `invoke-ncm-bridge.ps1 -Action verifyPlayback`：`NOT_VERIFIED` 诊断字段检查通过。
- `playSong -Verify`：SMTC 验证 `Eclipse - Aimer` 成功
- `playTheme -Verify`：SMTC 验证 `Eclipse - Aimer` 成功
