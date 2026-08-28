<#
主要作用：收集 ncm-bridge 所需运行环境的只读诊断信息。
输入：可选的配置路径与是否读取 SMTC 状态的开关。
输出：ncm-cli、登录、配置、脚本分析器和媒体会话诊断对象。
#>

$ErrorActionPreference = "Stop"

<#
主要作用：定位 ncm-cli 命令并读取其版本信息。
输入：无；依赖系统 PATH。
输出：可用性、命令路径、版本和错误信息组成的对象。
#>
function Get-NcmBridgeCommandInfo {
    $command = Get-Command "ncm-cli" -ErrorAction SilentlyContinue
    if (-not $command) {
        return [pscustomobject]@{
            available = $false
            path = $null
            version = $null
            error = "ncm-cli command not found"
        }
    }

    $version = $null
    $errorMessage = $null
    try {
        $version = (& ncm-cli --version).Trim()
    }
    catch {
        $errorMessage = $_.Exception.Message
    }

    [pscustomobject]@{
        available = $true
        path = "$($command.Source)"
        version = $version
        error = $errorMessage
    }
}

<#
主要作用：将 ncm-cli 登录检查转换为稳定的诊断字段。
输入：无；调用登录检查函数。
输出：是否已检查、是否登录成功及诊断消息组成的对象。
#>
function Get-NcmBridgeLoginInfo {
    try {
        Invoke-NcmCliLoginCheck
    }
    catch {
        [pscustomobject]@{
            success = $false
            message = $_.Exception.Message
            commandPath = $null
        }
    }
}

<#
主要作用：检测可选的 PSScriptAnalyzer 模块。
输入：无。
输出：分析器是否可用、版本、路径和说明组成的对象。
#>
function Get-NcmBridgeScriptAnalyzerInfo {
    $module = Get-Module -ListAvailable PSScriptAnalyzer |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $module) {
        return [pscustomobject]@{
            available = $false
            version = $null
            path = $null
            note = "PSScriptAnalyzer is optional and not installed."
        }
    }

    [pscustomobject]@{
        available = $true
        version = "$($module.Version)"
        path = "$($module.Path)"
        note = "PSScriptAnalyzer is available for optional static checks."
    }
}

<#
主要作用：汇总插件环境与登录状态，并按需加入 SMTC 读取结果。
输入：配置路径、是否验证媒体状态及 SMTC 重试参数。
输出：统一 diagnose 动作使用的完整诊断对象。
#>
function Get-NcmBridgeDiagnostics {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [bool]$IncludeSmtc = $false,
        [int]$SmtcAttempts = 1,
        [int]$SmtcRetryDelayMs = 0,
        [int]$SmtcInitialDelayMs = 0,
        [string]$RepoRoot = $null
    )

    $commandInfo = Get-NcmBridgeCommandInfo
    $loginInfo = Get-NcmBridgeLoginInfo
    $scriptAnalyzer = Get-NcmBridgeScriptAnalyzerInfo
    $configExists = Test-Path -LiteralPath $ConfigPath
    $smtc = $null

    if ($IncludeSmtc -and $loginInfo.success) {
        if (-not $RepoRoot) {
            $RepoRoot = Split-Path -Parent $PSScriptRoot
        }
        . (Join-Path $RepoRoot "netease-music-cli\OrpheusControl.ps1")
        $smtc = Get-NeteasePlaybackStatus -Attempts $SmtcAttempts -RetryDelayMs $SmtcRetryDelayMs -InitialDelayMs $SmtcInitialDelayMs
    }

    [pscustomobject]@{
        success = [bool]($commandInfo.available -and $loginInfo.success)
        action = "diagnose"
        code = if (-not $commandInfo.available) { "NCM_CLI_MISSING" } elseif (-not $loginInfo.success) { "LOGIN_REQUIRED" } else { "OK" }
        message = if (-not $commandInfo.available) {
            "ncm-cli command was not found."
        }
        elseif (-not $loginInfo.success) {
            "ncm-cli login is required before network, playlist, search, status, or SMTC actions."
        }
        else {
            "ncm-bridge preflight diagnostics completed."
        }
        ncmCli = $commandInfo
        login = [pscustomobject]@{
            checked = $true
            success = [bool]$loginInfo.success
            message = $loginInfo.message
        }
        config = [pscustomobject]@{
            path = $ConfigPath
            exists = [bool]$configExists
        }
        scriptAnalyzer = $scriptAnalyzer
        smtc = $smtc
        notes = @(
            "Login status must be checked before interpreting missing ncm-cli commands.",
            "Logged-out command lists can be incomplete and must not be treated as version evidence."
        )
    }
}
