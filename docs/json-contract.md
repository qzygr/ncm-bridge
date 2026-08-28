# JSON 契约

## 文档说明
该文档用于解释返回的结构化json：

```json
{
  "success": true,
  "action": "status",
  "code": "OK",
  "message": "供人阅读的摘要"
}
```

## 通用字段

- `success`：布尔型动作结果。对于启动类动作，`true` 可以表示协议 URL 已成功预览或发起，但除非 `verified` 同时为 `true`，否则不能证明播放状态已经改变。
- `action`：稳定的动作名称。
- `code`：稳定的机器可读代码。参见[代码值](#代码值)。
- `message`：简短的人工可读摘要。
- `dryRun`：布尔型预览标记。为 `true` 时，不应视为已写入远端或已发起真实播放。
- `verified`：布尔型播放验证标记。只有 SMTC 验证可以将其设为 `true`；`orpheus://` 成功、dry-run payload 生成成功或进程启动成功都必须保持为 `false`。

## 代码值

| 代码 | 含义 |
|---|---|
| `OK` | 动作已完成，不涉及特殊的预览、启动或播放验证状态。用于状态、搜索、修复、主题更新和歌单写入流程。 |
| `LOGIN_REQUIRED` | `ncm-cli login --check` 未确认登录成功。在登录成功前，不得根据缺失的命令、`unknown command` 或帮助输出缺项作出判断。 |
| `MISSING` | 状态检查发现已配置的歌单条目当前不健康或无法解析。 |
| `DRY_RUN` | 多步骤预览已完成，但未写入远端或发起真实播放，例如主题预览或 `playTheme -DryRun`。 |
| `URL_PREVIEWED` | 在 dry-run 模式下生成了 `orpheus://` 协议 URL。它没有被启动，也没有进行播放验证。 |
| `URL_LAUNCHED` | 已发起 `orpheus://` 协议 URL。这只确认启动路径已成功尝试，并不代表客户端已经开始播放目标内容。 |
| `VERIFIED` | SMTC 报告了期望的播放状态：标题匹配、歌手匹配且状态为 `Playing`。这是唯一能证明播放已切换到目标内容的代码。 |
| `NOT_VERIFIED` | SMTC 未在验证次数范围内报告期望播放状态。启动可能已经发生，但播放结果未被证实。 |

## 播放规则

`orpheus://` 启动成功永远不能证明播放已经改变。只有当 SMTC 返回期望的标题、歌手和 `Playing` 状态时，播放才算被验证。

对于播放动作：

- `success: true` 且 `code: URL_LAUNCHED` 表示协议 URL 启动路径已完成，但播放仍未验证。
- `success: true` 且 `code: VERIFIED` 表示 SMTC 已验证期望播放状态。
- `success: false` 且 `code: NOT_VERIFIED` 表示 SMTC 验证失败或超时。
- `dryRun: true` 始终表示没有发生播放验证。
- `verified: true` 只能在 SMTC 验证成功后出现。

## 搜索记录

`searchSong` 返回紧凑的记录：

```json
{
  "name": "Eclipse",
  "artists": ["Aimer"],
  "originalId": "2694779693",
  "encryptedId": "C9E8705B7783589DB2A3A80CADA71216",
  "album": "Eclipse",
  "duration": 235264
}
```

歌单编辑使用 `encryptedId`，`playSong` 使用 `originalId`。
