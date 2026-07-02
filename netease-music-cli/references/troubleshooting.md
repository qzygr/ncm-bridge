# 排障

## 未登录

只启动桌面登录窗口，然后停止：

```powershell
Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'
```

## active key 失效

症状：状态为 `missing`，原因是 `not_in_created_playlists`。

处理：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\repair-ncm-bridge-config.ps1 -Json
```

如果没有健康 key，先初始化：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\init-ncm-bridge-playlist.ps1 -Json
```

## orpheus 无响应

- 确认网易云音乐客户端已运行。
- 确认 `orpheus://` 协议已注册。
- 用 dry-run 只能验证 payload 生成：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-orpheus-dryrun.ps1
```

dry-run 不验证客户端是否执行。播放结果只能通过 SMTC 验证：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action verifyPlayback -ExpectedTitle "歌名" -ExpectedArtist "歌手" -Json
```

## SMTC 读不到状态

可能原因：

- 客户端未运行。
- 系统媒体会话关闭。
- 当前客户端没有暴露 SMTC 会话。

状态读取失败不代表播控一定失败。入口脚本的 `verifyPlayback` 会轮询 SMTC，直到目标歌名、歌手和 `Playing` 状态同时匹配，或直到尝试次数耗尽。

默认读取会先短暂等待并重试。需要调整时：

```powershell
powershell -ExecutionPolicy Bypass -File .\netease-music-cli\Read-NeteaseSmtc.ps1 -Json -Attempts 8 -RetryDelayMs 700 -InitialDelayMs 500
```
