param(
    [switch]$Json,
    [switch]$IncludePlayback,
    [string]$SearchKeyword = "Eclipse Aimer",
    [string]$ExactTitle = "Eclipse",
    [string]$Artist = "Aimer",
    [string]$OriginalId = "2694779693",
    [string]$ExpectedTitle = "Eclipse",
    [string]$ExpectedArtist = "Aimer"
)

$ErrorActionPreference = "Stop"
$outputJson = [bool]$Json

$LoginWindowCommand = "Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'"

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
$results = New-Object System.Collections.Generic.List[object]

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

$results.Add((Invoke-TestStep -Category "live" -Name "searchSong returns compact records" -Action {
    $result = Invoke-BridgeJson -Arguments @(
        "-ExecutionPolicy", "Bypass",
        "-File", $invokeScript,
        "-Action", "searchSong",
        "-Keyword", $SearchKeyword,
        "-ExactTitle", $ExactTitle,
        "-Artist", $Artist,
        "-Limit", "1",
        "-Json"
    )

    if ($result.action -ne "searchSong") { throw "Unexpected action: $($result.action)" }
    if ($result.count -lt 1) { throw "Expected at least one record." }
    if (-not $result.records[0].originalId -or -not $result.records[0].encryptedId) { throw "Missing compact IDs." }
    "found=$($result.records[0].name)"
}))

$results.Add((Invoke-TestStep -Category "live" -Name "SMTC read path returns JSON" -Action {
    $result = Invoke-BridgeJson -Arguments @(
        "-ExecutionPolicy", "Bypass",
        "-File", $invokeScript,
        "-Action", "verifyPlayback",
        "-ExpectedTitle", $ExpectedTitle,
        "-ExpectedArtist", $ExpectedArtist,
        "-Attempts", "1",
        "-RetryDelayMs", "0",
        "-InitialDelayMs", "0",
        "-Json"
    )

    if ($result.action -ne "verifyPlayback") { throw "Unexpected action: $($result.action)" }
    if (-not $result.smtc) { throw "Missing SMTC result." }
    "code=$($result.code)"
}))

if ($IncludePlayback) {
    $results.Add((Invoke-TestStep -Category "live-playback" -Name "playSong launches and verifies via SMTC" -Action {
        $result = Invoke-BridgeJson -Arguments @(
            "-ExecutionPolicy", "Bypass",
            "-File", $invokeScript,
            "-Action", "playSong",
            "-OriginalId", $OriginalId,
            "-ExpectedTitle", $ExpectedTitle,
            "-ExpectedArtist", $ExpectedArtist,
            "-Verify",
            "-Json"
        )

        if ($result.action -ne "playSong") { throw "Unexpected action: $($result.action)" }
        if ($result.code -ne "VERIFIED") { throw "Playback was not verified: $($result.code)" }
        if (-not $result.verified) { throw "Expected verified=true." }
        "verified=$($result.originalId)"
    }))
}
else {
    $results.Add((New-TestResult -Category "live-playback" -Name "playSong launches and verifies via SMTC" -Passed $true -Detail "Skipped. Re-run with -IncludePlayback to launch real playback."))
}

$summary = [pscustomobject]@{
    Total = $results.Count
    Passed = @($results | Where-Object { $_.Passed }).Count
    Failed = @($results | Where-Object { -not $_.Passed }).Count
}

$report = [pscustomobject]@{
    Success = ($summary.Failed -eq 0)
    Layer = "live"
    IncludesPlayback = [bool]$IncludePlayback
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
