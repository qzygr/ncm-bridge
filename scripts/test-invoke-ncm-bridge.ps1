param([switch]$Json)

$ErrorActionPreference = "Stop"
$outputJson = [bool]$Json

function New-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [string]$Detail = $null
    )

    [pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Detail = $Detail
    }
}

function Invoke-TestStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    try {
        $detail = & $Action
        New-TestResult -Name $Name -Passed $true -Detail $detail
    }
    catch {
        New-TestResult -Name $Name -Passed $false -Detail $_.Exception.Message
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$invokeScript = Join-Path $PSScriptRoot "invoke-ncm-bridge.ps1"
$results = New-Object System.Collections.Generic.List[object]

$results.Add((Invoke-TestStep -Name "orpheus dryRun action returns JSON" -Action {
    $raw = & powershell -ExecutionPolicy Bypass -File $invokeScript -Action dryRun -Json
    $result = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if (-not $result.Success -and -not $result.success) { throw "DryRun test failed." }
    "dryrun ok"
}))

$results.Add((Invoke-TestStep -Name "playDefault dry-run returns URL" -Action {
    $raw = & powershell -ExecutionPolicy Bypass -File $invokeScript -Action playDefault -DryRun -Json
    $result = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if ($result.action -ne "playDefault") { throw "Unexpected action: $($result.action)" }
    if ($result.playUrl -notmatch '^orpheus://') { throw "Missing orpheus URL." }
    "url ok"
}))

$results.Add((Invoke-TestStep -Name "searchSong returns compact records" -Action {
    $raw = & powershell -ExecutionPolicy Bypass -File $invokeScript -Action searchSong -Keyword "Eclipse Aimer" -ExactTitle "Eclipse" -Artist "Aimer" -Limit 1 -Json
    $result = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if ($result.action -ne "searchSong") { throw "Unexpected action: $($result.action)" }
    if ($result.count -lt 1) { throw "Expected at least one record." }
    if (-not $result.records[0].originalId -or -not $result.records[0].encryptedId) { throw "Missing compact IDs." }
    "found=$($result.records[0].name)"
}))

$results.Add((Invoke-TestStep -Name "compressed JSON returns one line" -Action {
    $raw = & powershell -ExecutionPolicy Bypass -File $invokeScript -Action status -Json -CompressJson
    if (@($raw).Count -ne 1) { throw "Expected one output line." }
    $result = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if ($result.action -ne "status") { throw "Unexpected action: $($result.action)" }
    if (-not $result.status) { throw "Missing status." }
    "compressed ok"
}))

$results.Add((Invoke-TestStep -Name "setTheme dry-run previews without remote write" -Action {
    $raw = & powershell -ExecutionPolicy Bypass -File $invokeScript -Action setTheme -Theme "Preview" -Description "Preview only." -DryRun -Json
    $result = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if ($result.code -ne "DRY_RUN") { throw "Unexpected code: $($result.code)" }
    "preview ok"
}))

$results.Add((Invoke-TestStep -Name "pruneMissing dry-run returns JSON" -Action {
    $raw = & powershell -ExecutionPolicy Bypass -File $invokeScript -Action pruneMissing -DryRun -Json
    $result = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if ($result.action -ne "repair") { throw "Unexpected action: $($result.action)" }
    if (-not $result.dryRun) { throw "Expected dryRun=true." }
    "prune preview ok"
}))

$results.Add((Invoke-TestStep -Name "playSong dry-run returns unverified URL" -Action {
    $raw = & powershell -ExecutionPolicy Bypass -File $invokeScript -Action playSong -OriginalId 2694779693 -DryRun -Json
    $result = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if ($result.action -ne "playSong") { throw "Unexpected action: $($result.action)" }
    if ($result.verified) { throw "Dry-run must not verify playback." }
    if ($result.code -ne "URL_PREVIEWED") { throw "Unexpected code: $($result.code)" }
    "url ok"
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

if ($outputJson) {
    $report | ConvertTo-Json -Depth 6
    exit
}

foreach ($item in $results) {
    $status = if ($item.Passed) { "[PASS]" } else { "[FAIL]" }
    $detail = if ($item.Detail) { " - $($item.Detail)" } else { "" }
    Write-Host "$status [invoke] $($item.Name)$detail"
}

Write-Host ""
Write-Host "Summary: $($summary.Passed)/$($summary.Total) passed, $($summary.Failed) failed."

if ($summary.Failed -gt 0) {
    exit 1
}
