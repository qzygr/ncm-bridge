$ErrorActionPreference = "Stop"

function Invoke-NcmCliJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

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
