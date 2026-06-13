param(
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$LoginWindowCommand = "Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'"

function New-TestResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [bool]$Passed,

        [string]$Detail = $null
    )

    [pscustomobject]@{
        Category = $Category
        Name = $Name
        Passed = $Passed
        Detail = $Detail
    }
}

function Invoke-TestStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    try {
        $detail = & $Action
        return New-TestResult -Category $Category -Name $Name -Passed $true -Detail $detail
    }
    catch {
        return New-TestResult -Category $Category -Name $Name -Passed $false -Detail $_.Exception.Message
    }
}

function Test-PowerShellSyntax {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "Syntax error: $($errors[0].Message)"
    }

    return "Syntax OK"
}

function Test-IsWindowsEnvironment {
    if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
        return [bool]$IsWindows
    }

    return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$orpheusScript = Join-Path $repoRoot "netease-music-cli\OrpheusControl.ps1"
$smtcScript = Join-Path $repoRoot "netease-music-cli\Read-NeteaseSmtc.ps1"
$registryPath = Join-Path $repoRoot "netease-music-cli\orpheus_commands.json"

$results = New-Object System.Collections.Generic.List[object]

$results.Add((Invoke-TestStep -Category "environment" -Name "operating system" -Action {
    if (-not (Test-IsWindowsEnvironment)) {
        throw "Current system is not Windows."
    }
    "Windows detected"
}))

$results.Add((Invoke-TestStep -Category "environment" -Name "PowerShell version" -Action {
    $version = $PSVersionTable.PSVersion
    if ($version.Major -lt 5) {
        throw "PowerShell version is too old: $version"
    }
    "PowerShell $version"
}))

$results.Add((Invoke-TestStep -Category "environment" -Name "Node.js" -Action {
    $nodeVersionText = (& node --version).Trim()
    if (-not $nodeVersionText) {
        throw "node --version returned no output."
    }

    $versionString = $nodeVersionText.TrimStart("v")
    $version = [Version]$versionString
    if ($version.Major -lt 18) {
        throw "Node.js version is too old: $nodeVersionText"
    }

    "Node.js $nodeVersionText"
}))

$results.Add((Invoke-TestStep -Category "environment" -Name "ncm-cli availability" -Action {
    $command = Get-Command "ncm-cli" -ErrorAction Stop
    $version = (& ncm-cli --version).Trim()
    if (-not $version) {
        throw "ncm-cli --version returned no output."
    }
    "ncm-cli $version ($($command.Source))"
}))

$results.Add((Invoke-TestStep -Category "login" -Name "account login status" -Action {
    $raw = & ncm-cli login --check
    if (-not $raw) {
        throw "ncm-cli login --check returned no output."
    }

    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    if (-not $parsed.success) {
        $message = if ($parsed.message) { $parsed.message } else { "Not logged in." }
        throw ($message + " Use the desktop login flow instead: " + $LoginWindowCommand + ". After launching it, stop here and wait for QR login to complete before rerunning this test.")
    }

    if ($parsed.message) {
        $parsed.message
    }
    else {
        "Logged in"
    }
}))

$results.Add((Invoke-TestStep -Category "integrity" -Name "required files" -Action {
    $requiredFiles = @(
        "README.md",
        "ncm-cli-setup\SKILL.md",
        "netease-music-cli\SKILL.md",
        "netease-music-cli\OrpheusControl.ps1",
        "netease-music-cli\Read-NeteaseSmtc.ps1",
        "netease-music-cli\orpheus_commands.json"
    )

    $missing = @()
    foreach ($relativePath in $requiredFiles) {
        $fullPath = Join-Path $repoRoot $relativePath
        if (-not (Test-Path $fullPath)) {
            $missing += $relativePath
        }
    }

    if ($missing.Count -gt 0) {
        throw "Missing files: $($missing -join ', ')"
    }

    "All required files exist"
}))

$results.Add((Invoke-TestStep -Category "integrity" -Name "orpheus registry" -Action {
    $registry = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if (-not $registry.commands -or $registry.commands.Count -eq 0) {
        throw "Registry commands list is empty."
    }

    $requiredCommands = @("next", "previous", "pause", "resume", "play_song", "play_playlist", "set_volume", "seek")
    $missing = @($requiredCommands | Where-Object { $_ -notin $registry.commands.name })
    if ($missing.Count -gt 0) {
        throw "Missing commands: $($missing -join ', ')"
    }

    "Command count: $($registry.commands.Count)"
}))

$results.Add((Invoke-TestStep -Category "integrity" -Name "PowerShell syntax" -Action {
    $orpheusResult = Test-PowerShellSyntax -Path $orpheusScript
    $smtcResult = Test-PowerShellSyntax -Path $smtcScript
    "$orpheusResult; $smtcResult"
}))

$results.Add((Invoke-TestStep -Category "integrity" -Name "module load and functions" -Action {
    . $orpheusScript

    $requiredFunctions = @(
        "OrpheusControl",
        "Invoke-OrpheusCommand",
        "Invoke-NcmCliJson",
        "Resolve-NcmPlaylistEncryptedId",
        "Invoke-NcmPlaylistControl",
        "Get-NeteasePlaybackStatus",
        "Get-OrpheusCommands",
        "Get-OrpheusControlFunctions"
    )

    $missing = @($requiredFunctions | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
    if ($missing.Count -gt 0) {
        throw "Missing functions: $($missing -join ', ')"
    }

    "Required functions are available"
}))

$summary = [pscustomobject]@{
    Total = $results.Count
    Passed = @($results | Where-Object { $_.Passed }).Count
    Failed = @($results | Where-Object { -not $_.Passed }).Count
}

$report = [pscustomobject]@{
    Success = ($summary.Failed -eq 0)
    Summary = $summary
    Results = $results
}

if ($Json) {
    $report | ConvertTo-Json -Depth 6
    exit
}

foreach ($item in $results) {
    $status = if ($item.Passed) { "[PASS]" } else { "[FAIL]" }
    $detail = if ($item.Detail) { " - $($item.Detail)" } else { "" }
    Write-Host "$status [$($item.Category)] $($item.Name)$detail"
}

Write-Host ""
Write-Host "Summary: $($summary.Passed)/$($summary.Total) passed, $($summary.Failed) failed."

if ($summary.Failed -gt 0) {
    exit 1
}
