param(
    [switch]$Json,
    [switch]$Live,
    [switch]$IncludePlayback
)

$ErrorActionPreference = "Stop"

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
$fastScript = Join-Path $PSScriptRoot "test-invoke-fast.ps1"
$liveScript = Join-Path $PSScriptRoot "test-invoke-live.ps1"

$results = New-Object System.Collections.Generic.List[object]

$results.Add((Invoke-TestStep -Category "fast" -Name "offline invoke layer" -Action {
    $arguments = @("-ExecutionPolicy", "Bypass", "-File", $fastScript, "-Json")
    $raw = & powershell @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "test-invoke-fast.ps1 failed."
    }

    $report = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if (-not $report.Success -and -not $report.success) {
        throw "test-invoke-fast.ps1 reported failure."
    }

    "$($report.Summary.Passed)/$($report.Summary.Total) passed"
}))

$results.Add((Invoke-TestStep -Category "environment" -Name "Node.js availability" -Action {
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

if ($Live) {
    $results.Add((Invoke-TestStep -Category "live" -Name "online invoke layer" -Action {
        $arguments = @("-ExecutionPolicy", "Bypass", "-File", $liveScript, "-Json")
        if ($IncludePlayback) { $arguments += "-IncludePlayback" }
        $raw = & powershell @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "test-invoke-live.ps1 failed."
        }

        $report = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
        if (-not $report.Success -and -not $report.success) {
            throw "test-invoke-live.ps1 reported failure."
        }

        "$($report.Summary.Passed)/$($report.Summary.Total) passed"
    }))
}
else {
    $results.Add((New-TestResult -Category "live" -Name "online invoke layer" -Passed $true -Detail "Skipped. Re-run with -Live for search/SMTC checks, add -IncludePlayback for real playback."))
}

$summary = [pscustomobject]@{
    Total = $results.Count
    Passed = @($results | Where-Object { $_.Passed }).Count
    Failed = @($results | Where-Object { -not $_.Passed }).Count
}

$report = [pscustomobject]@{
    Success = ($summary.Failed -eq 0)
    Layer = if ($Live) { "fast+live" } else { "fast" }
    IncludesPlayback = [bool]$IncludePlayback
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
