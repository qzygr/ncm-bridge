---
name: netease-music-cli
description: 使用 ncm-bridge 操作网易云音乐。用于搜索、点歌、播放主题歌单、查看状态、修复本地歌单配置和验证播放结果。
---

# ncm-bridge

## 必须先自检

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-ncm-bridge.ps1
```

- 默认自检只跑 fast：不联网、不远端写入、不真实播放、不读 SMTC。
- 任何联网搜索、歌单、状态、修复、远端写入预检、SMTC 路径或 `ncm-cli` 命令能力诊断前，必须先执行 `ncm-cli login --check`。
- 未登录时，`ncm-cli` 可能隐藏或缺失部分子命令；禁止据此判断版本不支持、命令不存在或脚本契约失效。
- 需要联网搜索和 SMTC 路径时，先确认 `ncm-cli login --check` 成功，再用 `.\scripts\test-ncm-bridge.ps1 -Live`。
- 需要真实播放验证时，再加 `-IncludePlayback`。
- 仅登录失败时，只启动登录窗口并停止等待用户扫码：

```powershell
Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'
```

启动登录窗口后必须暂停当前自动化流程，等待用户确认扫码完成；不要继续执行 `status`、`searchSong`、`playlist`、`commands`、`--help` 诊断或任何远端写入路径。

## 统一入口

优先使用 `invoke-ncm-bridge.ps1`，Agent 默认加 `-Json -CompressJson`：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action status -Json -CompressJson
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action searchSong -Keyword "Eclipse Aimer" -ExactTitle "Eclipse" -Artist "Aimer" -Limit 1 -Json -CompressJson
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action playSong -OriginalId "2694779693" -ExpectedTitle "Eclipse" -ExpectedArtist "Aimer" -Verify -Json -CompressJson
```

## 常用动作

```text
help / diagnose / status / repair / pruneMissing / searchSong / playSong / verifyPlayback
setTheme / validateReplaceTracks / replaceTracks / playTheme / dryRun
```

远端写入前优先预览：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action setTheme -Theme "主题" -Description "描述" -DryRun -Json -CompressJson
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action replaceTracks -SongIds "加密歌曲ID" -DryRun -Json -CompressJson
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action playTheme -Theme "主题" -SongIds "加密歌曲ID" -DryRun -Json -CompressJson
```

## 强约束

- 登录检查优先于命令能力判断：先 `ncm-cli login --check`，再检查 `search`、`playlist` 等命令是否可用。
- 未登录导致的 `unknown command`、命令列表缺失或帮助文本缺项，只能记录为“登录状态未确认/未登录下的无效诊断”，不能作为版本或脚本缺陷结论。
- `orpheus://` URL 发出不代表播放成功。
- dry-run 只验证 payload 生成，不验证客户端执行。
- 播放结果只能通过 SMTC 验证，使用 `-Verify` 或 `verifyPlayback`。
- `code: NOT_VERIFIED` 时查看 `verification.diagnostics` 或 `diagnostics`。
- 禁止使用 `ncm-cli play/pause/resume/stop/next/prev/seek/volume`。
- 搜索结果里：`encryptedId` 用于歌单编辑，`originalId` 用于播放。

## 细节文档

- `references/setup.md`
- `references/playlist-workflow.md`
- `references/troubleshooting.md`
- `references/json-contract.md`
