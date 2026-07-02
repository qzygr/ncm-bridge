param(
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$outputJson = [bool]$Json

function New-TestResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [bool]$Passed,

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
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    try {
        $detail = & $Action
        New-TestResult -Name $Name -Passed $true -Detail $detail
    }
    catch {
        New-TestResult -Name $Name -Passed $false -Detail $_.Exception.Message
    }
}

function ConvertFrom-OrpheusUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $prefix = "orpheus://"
    if (-not $Url.StartsWith($prefix)) {
        throw "URL does not start with $prefix"
    }

    $base64 = $Url.Substring($prefix.Length)
    $bytes = [Convert]::FromBase64String($base64)
    $jsonText = [System.Text.Encoding]::UTF8.GetString($bytes)
    $jsonText | ConvertFrom-Json -ErrorAction Stop
}

function Assert-PropertyEquals {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Property,

        [Parameter(Mandatory = $true)]
        [string]$Expected
    )

    $actual = "$($Object.$Property)"
    if ($actual -ne $Expected) {
        throw "$Property expected '$Expected', got '$actual'"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$orpheusScript = Join-Path $repoRoot "netease-music-cli\OrpheusControl.ps1"

. $orpheusScript

$cases = @(
    [pscustomobject]@{
        Name = "play_song dry-run payload"
        Command = "play_song"
        Params = @{ id = "2694779693" }
        Expected = @{ type = "song"; id = "2694779693"; cmd = "play" }
    },
    [pscustomobject]@{
        Name = "play_playlist dry-run payload"
        Command = "play_playlist"
        Params = @{ id = "18053129489" }
        Expected = @{ type = "playlist"; id = "18053129489"; cmd = "play" }
    },
    [pscustomobject]@{
        Name = "set_volume dry-run payload"
        Command = "set_volume"
        Params = @{ value = "30" }
        Expected = @{ cmd = "volume"; value = "30" }
    },
    [pscustomobject]@{
        Name = "seek dry-run payload"
        Command = "seek"
        Params = @{ value = "86.5" }
        Expected = @{ cmd = "seek"; value = "86.5" }
    }
)

$results = New-Object System.Collections.Generic.List[object]

foreach ($case in $cases) {
    $results.Add((Invoke-TestStep -Name $case.Name -Action {
        $url = Invoke-OrpheusCommand -Name $case.Command -Params $case.Params -DryRun 6>$null
        $payload = ConvertFrom-OrpheusUrl -Url $url

        foreach ($property in $case.Expected.Keys) {
            Assert-PropertyEquals -Object $payload -Property $property -Expected $case.Expected[$property]
        }

        "Decoded payload OK"
    }))
}

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
    Write-Host "$status [orpheus-dryrun] $($item.Name)$detail"
}

Write-Host ""
Write-Host "Summary: $($summary.Passed)/$($summary.Total) passed, $($summary.Failed) failed."

if ($summary.Failed -gt 0) {
    exit 1
}
