# OrpheusControl.ps1
# Local playback module. It only launches orpheus:// URLs and reads SMTC.
# A launched URL is not proof that playback changed; verify playback via SMTC.

$ErrorActionPreference = "Stop"

$smtcScriptPath = Join-Path $PSScriptRoot "Read-NeteaseSmtc.ps1"
if (Test-Path $smtcScriptPath) {
    . $smtcScriptPath
}

function OrpheusControl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json,

        [switch]$DryRun
    )

    try {
        $null = $Json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Error "[OrpheusControl] Invalid JSON input: $_"
        return
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $base64 = [Convert]::ToBase64String($bytes)
    $url = "orpheus://$base64"

    if ($DryRun) {
        Write-Host "[DryRun] $url"
    }
    else {
        try {
            Start-Process $url -ErrorAction Stop
            Write-Host "[OrpheusControl] Protocol URL launched: $url"
        }
        catch {
            Write-Error "[OrpheusControl] Failed to launch orpheus:// handler. Confirm Netease Cloud Music is installed and running."
        }
    }

    return $url
}

function Invoke-OrpheusCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [hashtable]$Params = @{},

        [string]$RegistryPath = $null,

        [switch]$DryRun
    )

    if (-not $RegistryPath) {
        $RegistryPath = Join-Path $PSScriptRoot "orpheus_commands.json"
    }

    if (-not (Test-Path $RegistryPath)) {
        Write-Error "[Invoke-OrpheusCommand] Registry not found: $RegistryPath"
        return
    }

    try {
        $registry = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Error "[Invoke-OrpheusCommand] Failed to parse registry JSON: $_"
        return
    }

    $cmdDef = $registry.commands | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $cmdDef) {
        $available = ($registry.commands | ForEach-Object { $_.name }) -join ', '
        Write-Error "[Invoke-OrpheusCommand] Unknown command '$Name'. Available: $available"
        return
    }

    $payload = $cmdDef.payload | ConvertTo-Json -Compress
    foreach ($key in $Params.Keys) {
        $placeholder = "`"`$$key`""
        $replacement = if ($Params[$key] -is [string]) {
            "`"$($Params[$key])`""
        }
        else {
            $Params[$key].ToString()
        }
        $payload = $payload.Replace($placeholder, $replacement)
    }

    if ($payload -match '\$\w+') {
        Write-Error "[Invoke-OrpheusCommand] Missing required params. Unresolved placeholders: $($matches.Values)"
        return
    }

    OrpheusControl -Json $payload -DryRun:$DryRun
}

function Get-NeteasePlaybackStatus {
    param(
        [int]$Attempts = 5,
        [int]$RetryDelayMs = 500,
        [int]$InitialDelayMs = 300
    )

    if (-not (Get-Command Invoke-NeteaseSmtcRead -ErrorAction SilentlyContinue)) {
        Write-Error "[Get-NeteasePlaybackStatus] SMTC reader not found: $smtcScriptPath"
        return $null
    }

    Invoke-NeteaseSmtcRead -Attempts $Attempts -RetryDelayMs $RetryDelayMs -InitialDelayMs $InitialDelayMs
}

function Get-OrpheusCommands {
    param([string]$RegistryPath = $null)

    if (-not $RegistryPath) {
        $RegistryPath = Join-Path $PSScriptRoot "orpheus_commands.json"
    }

    if (-not (Test-Path $RegistryPath)) {
        Write-Error "Registry not found: $RegistryPath"
        return
    }

    $registry = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $registry.commands | Format-Table name, description -AutoSize
}

function Get-OrpheusControlFunctions {
    param([string]$Path = $null)

    if (-not $Path) {
        $Path = if ($PSCommandPath) { $PSCommandPath } else { Join-Path $PSScriptRoot "OrpheusControl.ps1" }
    }

    if (-not (Test-Path $Path)) {
        Write-Error "Module file not found: $Path"
        return
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        Write-Error "Module parse failed: $($errors[0].Message)"
        return
    }

    $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        ForEach-Object {
            [pscustomobject]@{
                name = $_.Name
                line = $_.Extent.StartLineNumber
            }
        } |
        Sort-Object line |
        Format-Table name, line -AutoSize
}
