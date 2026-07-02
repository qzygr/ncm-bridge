---
name: netease-music-cli
description: 使用 ncm-bridge 操作网易云音乐。用于搜索、点歌、播放主题歌单、查看状态、修复本地歌单配置和验证播放结果。
---

# ncm-bridge

## 必须先自检

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-ncm-bridge.ps1
```

- `9/9` 通过后继续。
- 仅登录失败时，只启动登录窗口并停止等待用户扫码：

```powershell
Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'
```

## 统一入口

优先使用 `invoke-ncm-bridge.ps1`，Agent 默认加 `-Json -CompressJson`：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action status -Json -CompressJson
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action searchSong -Keyword "Eclipse Aimer" -ExactTitle "Eclipse" -Artist "Aimer" -Limit 1 -Json -CompressJson
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action playSong -OriginalId "2694779693" -ExpectedTitle "Eclipse" -ExpectedArtist "Aimer" -Verify -Json -CompressJson
```

## 常用动作

```text
status / repair / pruneMissing / searchSong / playSong / verifyPlayback
setTheme / validateReplaceTracks / replaceTracks / playTheme / dryRun
```

远端写入前优先预览：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action setTheme -Theme "主题" -Description "描述" -DryRun -Json -CompressJson
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action replaceTracks -SongIds "加密歌曲ID" -DryRun -Json -CompressJson
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action playTheme -Theme "主题" -SongIds "加密歌曲ID" -DryRun -Json -CompressJson
```

## 强约束

- `orpheus://` URL 发出不代表播放成功。
- dry-run 只验证 payload 生成，不验证客户端执行。
- 播放结果只能通过 SMTC 验证，使用 `-Verify` 或 `verifyPlayback`。
- 禁止使用 `ncm-cli play/pause/resume/stop/next/prev/seek/volume`。
- 搜索结果里：`encryptedId` 用于歌单编辑，`originalId` 用于播放。

## 细节文档

- `references/setup.md`
- `references/playlist-workflow.md`
- `references/troubleshooting.md`
- `references/json-contract.md`
