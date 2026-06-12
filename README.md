# ncm-bridge

网易云音乐 Skill 插件——让Agent帮你点歌。

## 架构

| 子系统 | 用途 | 工具 |
|--------|------|------|
| **数据层** | 搜索歌曲/歌单、获取 ID、歌单管理 | `ncm-cli` |
| **播控层** | 播放、暂停、切歌、音量控制 | `orpheus://` 协议（OrpheusControl.ps1） |
| **状态层** | 读取客户端会话、歌曲信息、播放状态 | Windows SMTC（Read-NeteaseSmtc.ps1） |

> ncm-cli 负责找，orpheus 负责播。泾渭分明。

## 目录结构

```
ncm-bridge/
├── ncm-cli-setup/
│   └── SKILL.md                 # 安装与配置指南
├── netease-music-cli/
│   ├── SKILL.md                 # 日常使用指南
│   ├── OrpheusControl.ps1       # 播控函数模块
│   ├── Read-NeteaseSmtc.ps1     # 基于 SMTC 的状态读取脚本
│   └── orpheus_commands.json    # 播控命令注册表
└── README.md
```

## 环境要求

- **操作系统**：仅Windows（MacOS请直接使用ncm-cli连接）
- **Node.js** ≥ 18
- **网易云音乐客户端**：已正确安装并可运行
- **ncm-cli**：`npm install -g @music163/ncm-cli`
- **API Key**：前往[网易云音乐开放平台](https://developer.music.163.com/)申请

## 快速开始

### 1. 安装 ncm-cli

```powershell
npm install -g @music163/ncm-cli
```

### 2. 配置 API Key

```powershell
ncm-cli config set appId <你的AppId>
ncm-cli config set privateKey <你的PrivateKey>
```

### 3. 登录

```powershell
Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'
```

执行后请在弹出的 PowerShell 窗口中完成扫码登录。登录是否完成以 `ncm-cli login --check` 为准；`ncm-cli state` 只反映客户端/播放状态，不用于判断账号登录。

### 4. 加载 Skill

将 `ncm-cli-setup` 和 `netease-music-cli` 安装到 Agent 的 skills 目录。
（其实这步最重要，前三点都不是必要的，Agent会自动帮你搞定这几点）
（你让 Agent 读取这个文件夹，然后让它安装这个东西，就能用了）

## 使用示例

> 博士：普瑞赛斯，点一首 Eclipse

> 普瑞赛斯：（搜索 → 找到 Aimer × 塞壬唱片-MSR → 播放）
> 指令已发送。Eclipse，你应该能听到了。

## 注意事项

- 播控命令（play/pause/next 等）通过 `orpheus://` 协议发送，禁止直接使用 `ncm-cli` 的播控子命令
- `play_song` 和 `play_playlist` 的 `id` 参数必须使用原始数字 ID，而非加密 ID
- 登录环节如遇超时，使用 `Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'` 弹出登录窗口并完成扫码
- `ncm-cli state` 不适合作为 `orpheus://` 播控是否生效的判断依据，请以客户端窗口、UI 状态或用户听感反馈为准
- `Get-NeteasePlaybackStatus` 依赖 Windows SMTC；如果客户端未运行、系统关闭了媒体会话能力，或当前会话未暴露给 SMTC，读取会失败
- `Invoke-NcmCliJson` 不再只依赖默认 `%APPDATA%` 路径，会优先从 `PATH` 中解析 `ncm-cli` 的安装位置

---

> 博士。不准忘记我。
>
> —— 普瑞赛斯
