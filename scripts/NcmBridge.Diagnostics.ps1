$ErrorActionPreference = "Stop"

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
