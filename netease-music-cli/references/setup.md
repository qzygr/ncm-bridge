# 安装与登录

## 环境

- Windows
- PowerShell
- Node.js >= 18
- 网易云音乐客户端已安装并可运行
- `ncm-cli`

## 安装 ncm-cli

```powershell
npm install -g @music163/ncm-cli
ncm-cli --version
```

## 配置 API Key

```powershell
ncm-cli config set appId <AppId>
ncm-cli config set privateKey <PrivateKey>
```

如果没有 API Key，到网易云音乐开放平台申请。

## 登录

不要直接运行 `ncm-cli login --background`。必须弹出桌面窗口：

```powershell
Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'
```

启动后停止自动流程，等用户扫码完成，再跑：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-ncm-bridge.ps1
```
