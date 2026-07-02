param([switch]$Json)

$ErrorActionPreference = "Stop"
$outputJson = [bool]$Json

function New-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
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
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    try {
        $detail = & $Action
        New-TestResult -Category $Category -Name $Name -Passed $true -Detail $detail
    }
    catch {
        New-TestResult -Category $Category -Name $Name -Passed $false -Detail $_.Exception.Message
    }
}

function Test-PowerShellSyntax {
    param([Parameter(Mandatory = $true)][string]$Path)

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "Syntax error in $Path`: $($errors[0].Message)"
    }

    "Syntax OK"
}

function Test-IsWindowsEnvironment {
    if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
        return [bool]$IsWindows
    }

    return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

function Invoke-BridgeJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $raw = & powershell @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: powershell $($Arguments -join ' ')"
    }

    ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$invokeScript = Join-Path $PSScriptRoot "invoke-ncm-bridge.ps1"
$payloadScript = Join-Path $PSScriptRoot "test-orpheus-payload.ps1"
$tmpRoot = Join-Path $repoRoot ".codex-tmp"
$fastConfigPath = Join-Path $tmpRoot "test-invoke-fast.ncm-bridge.json"

if (-not (Test-Path $tmpRoot)) {
    New-Item -ItemType Directory -Path $tmpRoot | Out-Null
}

$fastConfig = [pscustomobject]@{
    activePlaylistKey = "default"
    bridgePlaylists = [pscustomobject]@{
        default = [pscustomobject]@{
            key = "default"
            baseName = "ncm-bridge"
            roleName = "Agent"
            displayName = "ncm-bridge - Agent"
            originalId = "18053129489"
            encryptedId = "0123456789ABCDEFFEDCBA9876543210"
        }
    }
}
$fastConfig | ConvertTo-Json -Depth 8 | Set-Content -Path $fastConfigPath -Encoding UTF8

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

$results.Add((Invoke-TestStep -Category "integrity" -Name "required files" -Action {
    $requiredFiles = @(
        "README.md",
        "ncm-cli-setup\SKILL.md",
        "netease-music-cli\SKILL.md",
        "netease-music-cli\OrpheusControl.ps1",
        "netease-music-cli\Read-NeteaseSmtc.ps1",
        "netease-music-cli\orpheus_commands.json",
        "scripts\NcmBridge.Cli.ps1",
        "scripts\NcmBridge.Config.ps1",
        "scripts\NcmBridge.Help.ps1",
        "scripts\NcmBridge.Text.ps1",
        "scripts\NcmBridge.Playlist.ps1",
        "scripts\repair-ncm-bridge-config.ps1",
        "scripts\invoke-ncm-bridge.ps1",
        "scripts\test-invoke-fast.ps1",
        "scripts\test-invoke-live.ps1",
        "scripts\test-invoke-ncm-bridge.ps1",
        "scripts\test-ncm-bridge.ps1",
        "scripts\test-orpheus-payload.ps1"
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
    $registryPath = Join-Path $repoRoot "netease-music-cli\orpheus_commands.json"
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
    $paths = @(
        (Join-Path $repoRoot "netease-music-cli\OrpheusControl.ps1"),
        (Join-Path $repoRoot "netease-music-cli\Read-NeteaseSmtc.ps1"),
        (Join-Path $repoRoot "scripts\NcmBridge.Cli.ps1"),
        (Join-Path $repoRoot "scripts\NcmBridge.Config.ps1"),
        (Join-Path $repoRoot "scripts\NcmBridge.Help.ps1"),
        (Join-Path $repoRoot "scripts\NcmBridge.Text.ps1"),
        (Join-Path $repoRoot "scripts\NcmBridge.Playlist.ps1"),
        (Join-Path $repoRoot "scripts\get-ncm-bridge-status.ps1"),
        (Join-Path $repoRoot "scripts\init-ncm-bridge-playlist.ps1"),
        (Join-Path $repoRoot "scripts\invoke-ncm-bridge.ps1"),
        (Join-Path $repoRoot "scripts\repair-ncm-bridge-config.ps1"),
        (Join-Path $repoRoot "scripts\replace-ncm-bridge-tracks.ps1"),
        (Join-Path $repoRoot "scripts\set-ncm-bridge-theme.ps1"),
        (Join-Path $repoRoot "scripts\play-ncm-bridge-theme.ps1"),
        (Join-Path $repoRoot "scripts\test-invoke-fast.ps1"),
        (Join-Path $repoRoot "scripts\test-invoke-live.ps1"),
        (Join-Path $repoRoot "scripts\test-invoke-ncm-bridge.ps1"),
        (Join-Path $repoRoot "scripts\test-ncm-bridge.ps1"),
        (Join-Path $repoRoot "scripts\test-orpheus-payload.ps1")
    )

    foreach ($path in $paths) {
        $null = Test-PowerShellSyntax -Path $path
    }
    "Syntax OK: $($paths.Count) files"
}))

$results.Add((Invoke-TestStep -Category "integrity" -Name "module load and functions" -Action {
    . (Join-Path $repoRoot "netease-music-cli\OrpheusControl.ps1")
    . (Join-Path $repoRoot "scripts\NcmBridge.Cli.ps1")
    . (Join-Path $repoRoot "scripts\NcmBridge.Playlist.ps1")

    $requiredFunctions = @(
        "OrpheusControl",
        "Invoke-OrpheusCommand",
        "Invoke-NcmCliJson",
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

$results.Add((Invoke-TestStep -Category "invoke-fast" -Name "orpheus dryRun action returns JSON" -Action {
    $result = Invoke-BridgeJson -Arguments @("-ExecutionPolicy", "Bypass", "-File", $invokeScript, "-Action", "dryRun", "-Json")
    if (-not $result.Success -and -not $result.success) { throw "DryRun action failed." }
    if ($result.Summary.Failed -gt 0) { throw "Payload tests failed." }
    "dryrun ok"
}))

$results.Add((Invoke-TestStep -Category "invoke-fast" -Name "payload test returns JSON" -Action {
    $result = Invoke-BridgeJson -Arguments @("-ExecutionPolicy", "Bypass", "-File", $payloadScript, "-Json")
    if (-not $result.Success -and -not $result.success) { throw "Payload test failed." }
    if ($result.Summary.Failed -gt 0) { throw "Payload tests failed." }
    "payload ok"
}))

$results.Add((Invoke-TestStep -Category "invoke-fast" -Name "playDefault dry-run returns URL" -Action {
    $result = Invoke-BridgeJson -Arguments @("-ExecutionPolicy", "Bypass", "-File", $invokeScript, "-Action", "playDefault", "-ConfigPath", $fastConfigPath, "-DryRun", "-Json")
    if ($result.action -ne "playDefault") { throw "Unexpected action: $($result.action)" }
    if (-not $result.dryRun) { throw "Expected dryRun=true." }
    if ($result.verified) { throw "Dry-run must not verify playback." }
    if ($result.playUrl -notmatch '^orpheus://') { throw "Missing orpheus URL." }
    "url ok"
}))

$results.Add((Invoke-TestStep -Category "invoke-fast" -Name "playSong dry-run returns unverified URL" -Action {
    $result = Invoke-BridgeJson -Arguments @("-ExecutionPolicy", "Bypass", "-File", $invokeScript, "-Action", "playSong", "-OriginalId", "2694779693", "-DryRun", "-Json")
    if ($result.action -ne "playSong") { throw "Unexpected action: $($result.action)" }
    if (-not $result.dryRun) { throw "Expected dryRun=true." }
    if ($result.verified) { throw "Dry-run must not verify playback." }
    if ($result.code -ne "URL_PREVIEWED") { throw "Unexpected code: $($result.code)" }
    if ($result.playUrl -notmatch '^orpheus://') { throw "Missing orpheus URL." }
    "url ok"
}))

$results.Add((Invoke-TestStep -Category "invoke-fast" -Name "setTheme dry-run previews without remote write" -Action {
    $result = Invoke-BridgeJson -Arguments @("-ExecutionPolicy", "Bypass", "-File", $invokeScript, "-Action", "setTheme", "-Theme", "Preview", "-Description", "Preview only.", "-ConfigPath", $fastConfigPath, "-DryRun", "-Json")
    if ($result.action -ne "previewSetTheme") { throw "Unexpected action: $($result.action)" }
    if ($result.code -ne "DRY_RUN") { throw "Unexpected code: $($result.code)" }
    if (-not $result.dryRun) { throw "Expected dryRun=true." }
    "preview ok"
}))

$results.Add((Invoke-TestStep -Category "invoke-fast" -Name "compressed JSON returns one line without network" -Action {
    $raw = & powershell -ExecutionPolicy Bypass -File $invokeScript -Action playSong -OriginalId 2694779693 -DryRun -Json -CompressJson
    if ($LASTEXITCODE -ne 0) { throw "Compressed JSON command failed." }
    if (@($raw).Count -ne 1) { throw "Expected one output line." }
    $result = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if ($result.action -ne "playSong") { throw "Unexpected action: $($result.action)" }
    "compressed ok"
}))

$summary = [pscustomobject]@{
    Total = $results.Count
    Passed = @($results | Where-Object { $_.Passed }).Count
    Failed = @($results | Where-Object { -not $_.Passed }).Count
}

$report = [pscustomobject]@{
    Success = ($summary.Failed -eq 0)
    Layer = "fast"
    Guarantees = @(
        "no ncm-cli network calls",
        "no remote writes",
        "no real playback",
        "no SMTC reads"
    )
    Summary = $summary
    Results = $results
}

if ($outputJson) {
    $report | ConvertTo-Json -Depth 8
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
