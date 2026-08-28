<#
主要作用：编码并发起网易云音乐客户端的 orpheus:// 本地协议命令。
输入：协议 JSON、命令注册表路径、DryRun 与 JSON 输出开关。
输出：协议 URL、命令列表、播放状态或命令执行结果。
#>

$ErrorActionPreference = "Stop"

$smtcScriptPath = Join-Path $PSScriptRoot "Read-NeteaseSmtc.ps1"
if (Test-Path $smtcScriptPath) {
    . $smtcScriptPath
}

<#
主要作用：将 JSON 负载编码为标准 Base64 的 orpheus:// 协议 URL，并可选择启动。
输入：JSON 负载、是否 DryRun、是否以 JSON 格式返回。
输出：生成的协议 URL；DryRun 时仅返回预览，不启动客户端。
#>
function OrpheusControl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json,

        [switch]$DryRun
    )

    try {
        $null = $Json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Error "[OrpheusControl] Invalid JSON input: $_"
        return
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $base64 = [Convert]::ToBase64String($bytes)
    $url = "orpheus://$base64"

    if ($DryRun) {
        Write-Host "[DryRun] $url"
    }
    else {
        try {
            Start-Process $url -ErrorAction Stop
            Write-Host "[OrpheusControl] Protocol URL launched: $url"
        }
        catch {
            Write-Error "[OrpheusControl] Failed to launch orpheus:// handler. Confirm Netease Cloud Music is installed and running."
        }
    }

    return $url
}

<#
主要作用：根据命令名称和参数构造并执行 Orpheus 注册表中的协议命令。
输入：命令名称、ID、数值、DryRun、注册表路径和 JSON 开关。
输出：协议调用结果对象或协议 URL。
#>
function Invoke-OrpheusCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [hashtable]$Params = @{},

        [string]$RegistryPath = $null,

        [switch]$DryRun
    )

    if (-not $RegistryPath) {
        $RegistryPath = Join-Path $PSScriptRoot "protocol\orpheus_commands.json"
    }

    if (-not (Test-Path $RegistryPath)) {
        Write-Error "[Invoke-OrpheusCommand] Registry not found: $RegistryPath"
        return
    }

    try {
        $registry = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Error "[Invoke-OrpheusCommand] Failed to parse registry JSON: $_"
        return
    }

    $cmdDef = $registry.commands | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $cmdDef) {
        $available = ($registry.commands | ForEach-Object { $_.name }) -join ', '
        Write-Error "[Invoke-OrpheusCommand] Unknown command '$Name'. Available: $available"
        return
    }

    $payload = $cmdDef.payload | ConvertTo-Json -Compress
    foreach ($key in $Params.Keys) {
        $placeholder = "`"`$$key`""
        $replacement = if ($Params[$key] -is [string]) {
            "`"$($Params[$key])`""
        }
        else {
            $Params[$key].ToString()
        }
        $payload = $payload.Replace($placeholder, $replacement)
    }

    if ($payload -match '\$\w+') {
        Write-Error "[Invoke-OrpheusCommand] Missing required params. Unresolved placeholders: $($matches.Values)"
        return
    }

    OrpheusControl -Json $payload -DryRun:$DryRun
}

<#
主要作用：读取网易云音乐客户端当前播放状态的兼容包装。
输入：SMTC 初始等待、重试次数与重试延迟。
输出：Read-NeteaseSmtc.ps1 返回的媒体会话状态对象。
#>
function Get-NeteasePlaybackStatus {
    param(
        [int]$Attempts = 5,
        [int]$RetryDelayMs = 500,
        [int]$InitialDelayMs = 300
    )

    if (-not (Get-Command Invoke-NeteaseSmtcRead -ErrorAction SilentlyContinue)) {
        Write-Error "[Get-NeteasePlaybackStatus] SMTC reader not found: $smtcScriptPath"
        return $null
    }

    Invoke-NeteaseSmtcRead -Attempts $Attempts -RetryDelayMs $RetryDelayMs -InitialDelayMs $InitialDelayMs
}

<#
主要作用：读取并返回 Orpheus 命令注册表。
输入：可选的注册表 JSON 文件路径。
输出：命令注册表对象，包含协议名称、命令和编码规则。
#>
function Get-OrpheusCommands {
    param([string]$RegistryPath = $null)

    if (-not $RegistryPath) {
        $RegistryPath = Join-Path $PSScriptRoot "protocol\orpheus_commands.json"
    }

    if (-not (Test-Path $RegistryPath)) {
        Write-Error "Registry not found: $RegistryPath"
        return
    }

    $registry = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $registry.commands | Format-Table name, description -AutoSize
}

<#
主要作用：列出此模块公开的 Orpheus 控制函数名称。
输入：可选模块路径，用于读取函数定义。
输出：公开函数名称字符串数组。
#>
function Get-OrpheusControlFunctions {
    param([string]$Path = $null)

    if (-not $Path) {
        $Path = if ($PSCommandPath) { $PSCommandPath } else { Join-Path $PSScriptRoot "OrpheusControl.ps1" }
    }

    if (-not (Test-Path $Path)) {
        Write-Error "Module file not found: $Path"
        return
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        Write-Error "Module parse failed: $($errors[0].Message)"
        return
    }

    $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        ForEach-Object {
            [pscustomobject]@{
                name = $_.Name
                line = $_.Extent.StartLineNumber
            }
        } |
        Sort-Object line |
        Format-Table name, line -AutoSize
}
