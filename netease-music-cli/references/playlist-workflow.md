# 程序专用歌单工作流

## 配置

`.ncm-bridge.json` 保存本地绑定，不提交仓库。一个 `PlaylistKey` 对应一个程序专用歌单：

```json
{
  "activePlaylistKey": "default",
  "bridgePlaylists": {
    "default": {
      "originalId": "播放用原始ID",
      "encryptedId": "管理用加密ID"
    }
  }
}
```

## 状态

短输出优先给 Agent 使用：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action status -Json
```

Agent 高密度调用可压缩 JSON：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action status -Json -CompressJson
```

查看所有 key：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\get-ncm-bridge-status.ps1 -All -Json
```

## 修复

当 active key 指向失效歌单时：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action repair -Json
```

预览：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action repair -DryRun -Json
```

清理失效 key 的预览：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action pruneMissing -DryRun -Json
```

移除失效 key：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\repair-ncm-bridge-config.ps1 -PruneMissing -Json
```

## 初始化

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\init-ncm-bridge-playlist.ps1 -PlaylistKey "default" -BaseName "ncm-bridge" -RoleName "普瑞赛斯" -Json
```

## 设置主题

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\set-ncm-bridge-theme.ps1 -Theme "夜间助眠" -Description "低动态、慢节奏，适合入睡前播放。" -Json
```

## 替换曲目

`SongIds` 使用加密歌曲 ID。

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action validateReplaceTracks -SongIds "加密歌曲ID1,加密歌曲ID2" -Json
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action replaceTracks -SongIds "加密歌曲ID1,加密歌曲ID2" -Json
```

## 主题播放

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action playTheme -Theme "夜间助眠" -Description "低动态、慢节奏，适合入睡前播放。" -SongIds "加密歌曲ID1,加密歌曲ID2" -Json
```
