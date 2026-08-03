$ErrorActionPreference = "Stop"

function Test-NcmBridgeActionRequiresLogin {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [bool]$DryRun = $false,
        [bool]$Verify = $false
    )

    switch ($Action) {
        "status" { return $true }
        "repair" { return $true }
        "pruneMissing" { return $true }
        "searchSong" { return $true }
        "validateReplaceTracks" { return $true }
        "replaceTracks" { return $true }
        "playTheme" { return $true }
        "setTheme" { return -not $DryRun }
        "verifyPlayback" { return $true }
        "playSong" { return $Verify -and -not $DryRun }
        default { return $false }
    }
}

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
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $null = Assert-NcmCliLoggedIn

    $command = Get-Command "ncm-cli" -ErrorAction SilentlyContinue
    $cliPath = $null
    if ($command -and $command.Source) {
        $commandDir = Split-Path -Parent $command.Source
        $candidatePath = Join-Path $commandDir "node_modules\@music163\ncm-cli\dist\index.js"
        if (Test-Path -LiteralPath $candidatePath) {
            $cliPath = $candidatePath
        }
    }

    if (-not $cliPath) {
        $fallbackPath = Join-Path $env:APPDATA "npm\node_modules\@music163\ncm-cli\dist\index.js"
        if (Test-Path -LiteralPath $fallbackPath) {
            $cliPath = $fallbackPath
        }
    }

    if (-not $cliPath) {
        throw "ncm-cli entry point was not found. Install @music163/ncm-cli globally."
    }

    function ConvertTo-WindowsArgument {
        param([Parameter(Mandatory = $true)][string]$Value)

        if ($Value -notmatch '[\s"]') {
            return $Value
        }

        $builder = [System.Text.StringBuilder]::new()
        [void]$builder.Append('"')
        $backslashCount = 0

        foreach ($char in $Value.ToCharArray()) {
            if ($char -eq '\') {
                $backslashCount++
                continue
            }

            if ($char -eq '"') {
                [void]$builder.Append(('\' * (($backslashCount * 2) + 1)))
                [void]$builder.Append('"')
                $backslashCount = 0
                continue
            }

            if ($backslashCount -gt 0) {
                [void]$builder.Append(('\' * $backslashCount))
                $backslashCount = 0
            }
            [void]$builder.Append($char)
        }

        if ($backslashCount -gt 0) {
            [void]$builder.Append(('\' * ($backslashCount * 2)))
        }
        [void]$builder.Append('"')
        $builder.ToString()
    }

    $allArguments = @($cliPath) + $Arguments
    $argumentText = ($allArguments | ForEach-Object { ConvertTo-WindowsArgument -Value "$_" }) -join " "
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = "node"
    $processInfo.Arguments = $argumentText
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = [System.Diagnostics.Process]::Start($processInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($stderr) {
        throw "ncm-cli stderr: $stderr"
    }
    if ($process.ExitCode -ne 0) {
        throw "ncm-cli exited with code $($process.ExitCode)`n$stdout"
    }
    if (-not $stdout.Trim()) {
        throw "ncm-cli returned no output: $($Arguments -join ' ')"
    }

    try {
        return $stdout | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "ncm-cli output is not valid JSON: $stdout"
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
