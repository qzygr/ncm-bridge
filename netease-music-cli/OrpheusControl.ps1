# OrpheusControl.ps1
# 网易云音乐本地服务控制模块（基于 orpheus:// 协议）
# 用法：. .\OrpheusControl.ps1    （dot-source 加载）
#       OrpheusControl -Json '{"cmd":"next"}'
#       Invoke-OrpheusCommand -Name "next"

# ============================================================
# 核心函数：将 JSON 指令编码为 orpheus:// 协议 URL 并执行
# 编码方式：UTF-8 → 标准 Base64（含尾部 = 填充）
# ============================================================
function OrpheusControl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json,

        [switch]$DryRun
    )

    # 校验 JSON 合法性
    try {
        $null = $Json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Error "[OrpheusControl] 无效的 JSON 输入: $_"
        return
    }

    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $base64 = [Convert]::ToBase64String($bytes)
    $url    = "orpheus://$base64"

    if ($DryRun) {
        Write-Host "[DryRun] $url"
    }
    else {
        try {
            Start-Process $url -ErrorAction Stop
            Write-Host "[OrpheusControl] 指令已发送: $url"
        }
        catch {
            Write-Error "[OrpheusControl] 无法启动协议处理器，请确认网易云客户端已运行且 orpheus:// 协议已注册。"
        }
    }

    return $url
}

# ============================================================
# 便捷函数：从 JSON 注册表按名称查找命令并执行
# ============================================================
function Invoke-OrpheusCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [hashtable]$Params = @{},

        [string]$RegistryPath = $null,

        [switch]$DryRun
    )

    if (-not $RegistryPath) {
        $RegistryPath = Join-Path $PSScriptRoot "orpheus_commands.json"
    }

    if (-not (Test-Path $RegistryPath)) {
        Write-Error "[Invoke-OrpheusCommand] 注册表未找到: $RegistryPath"
        return
    }

    try {
        $registry = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Error "[Invoke-OrpheusCommand] JSON 解析失败: $_"
        return
    }

    $cmdDef = $registry.commands | Where-Object { $_.name -eq $Name }
    if (-not $cmdDef) {
        $available = ($registry.commands | ForEach-Object { $_.name }) -join ', '
        Write-Error "[Invoke-OrpheusCommand] 未知命令 '$Name'。可用: $available"
        return
    }

    # 将 payload 序列化为紧凑 JSON
    $payload = $cmdDef.payload | ConvertTo-Json -Compress

    # 替换占位符（$value, $id 等）
    foreach ($key in $Params.Keys) {
        $placeholder = "`"`$$key`""
        $replacement = if ($Params[$key] -is [string]) {
            "`"$($Params[$key])`""
        } else {
            $Params[$key].ToString()
        }
        $payload = $payload.Replace($placeholder, $replacement)
    }

    if ($payload -match '\$\w+') {
        Write-Warning "[Invoke-OrpheusCommand] 仍有未替换的占位符: $($matches.Values)"
    }

    OrpheusControl -Json $payload -DryRun:$DryRun
}

# ============================================================
# 便捷函数：列出所有可用命令
# ============================================================
function Get-OrpheusCommands {
    param(
        [string]$RegistryPath = $null
    )

    if (-not $RegistryPath) {
        $RegistryPath = Join-Path $PSScriptRoot "orpheus_commands.json"
    }

    if (-not (Test-Path $RegistryPath)) {
        Write-Error "注册表未找到: $RegistryPath"
        return
    }

    $registry = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $registry.commands | Format-Table name, description -AutoSize
}
