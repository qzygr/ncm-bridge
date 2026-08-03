$ErrorActionPreference = "Stop"

function Invoke-NcmCliLoginCheck {
    $command = Get-Command "ncm-cli" -ErrorAction Stop
    $raw = & ncm-cli login --check
    if (-not $raw) {
        throw "ncm-cli login --check returned no output."
    }

    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    [pscustomobject]@{
        success = [bool]$parsed.success
        message = if ($parsed.message) { "$($parsed.message)" } else { $null }
        commandPath = "$($command.Source)"
    }
}

function New-NcmCliLoginRequiredResult {
    param(
        [object]$LoginStatus = $null,
        [string]$ActionName = "loginCheck"
    )

    [pscustomobject]@{
        success = $false
        action = $ActionName
        code = "LOGIN_REQUIRED"
        message = if ($LoginStatus -and $LoginStatus.message) { "$($LoginStatus.message)" } else { "ncm-cli login is required before this action." }
        login = [pscustomobject]@{
            checked = $true
            success = $false
            message = if ($LoginStatus -and $LoginStatus.message) { "$($LoginStatus.message)" } else { $null }
        }
        nextAction = "Start desktop login flow and wait for QR login to complete before retrying."
        loginCommand = "Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'"
    }
}

function Assert-NcmCliLoggedIn {
    $status = Invoke-NcmCliLoginCheck
    if (-not $status.success) {
        $result = New-NcmCliLoginRequiredResult -LoginStatus $status
        throw "$($result.code): $($result.message)"
    }

    $status
}

function Invoke-NcmCliJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $null = Assert-NcmCliLoggedIn
    $output = & ncm-cli @Arguments
    if (-not $output) {
        throw "ncm-cli returned no output: $($Arguments -join ' ')"
    }

    $raw = $output -join "`n"
    try {
        return $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "ncm-cli output is not valid JSON: $raw"
    }
}

function Assert-NcmCliOk {
    param(
        [Parameter(Mandatory = $true)][object]$Response,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Response.code -ne 200) {
        throw "${Message}: $($Response.message)"
    }
}
