param(
    [string]$Prefer = "",
    [string]$ConfigPath = $null,
    [switch]$PruneMissing,
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$outputJson = [bool]$Json

. (Join-Path $PSScriptRoot "NcmBridge.Cli.ps1")
. (Join-Path $PSScriptRoot "NcmBridge.Config.ps1")
. (Join-Path $PSScriptRoot "NcmBridge.Playlist.ps1")

if (-not $ConfigPath) {
    $ConfigPath = Get-NcmBridgeDefaultConfigPath
}

$config = Read-BridgeConfig -Path $ConfigPath
$createdPlaylists = Get-CreatedPlaylists
$keys = Get-BridgePlaylistKeys -Config $config

$items = foreach ($key in $keys) {
    $entry = Get-BridgePlaylistEntry -Config $config -Key $key
    $remote = if ($entry) { Find-CreatedPlaylistByEntry -CreatedPlaylists $createdPlaylists -Entry $entry } else { $null }
    [pscustomobject]@{
        playlistKey = $key
        status = if ($remote) { "ok" } else { "missing" }
        entry = $entry
        remote = $remote
    }
}

$healthy = @($items | Where-Object { $_.status -eq "ok" })
$selected = $null
$preferValue = $Prefer.Trim()

if (-not [string]::IsNullOrWhiteSpace($preferValue)) {
    $selected = $healthy | Where-Object { $_.playlistKey -eq $preferValue } | Select-Object -First 1
    if (-not $selected) {
        throw "Preferred PlaylistKey '$preferValue' is not healthy."
    }
}
elseif ($config.activePlaylistKey) {
    $selected = $healthy | Where-Object { $_.playlistKey -eq "$($config.activePlaylistKey)" } | Select-Object -First 1
}

if (-not $selected) {
    $selected = $healthy | Where-Object { $_.playlistKey -eq "default" } | Select-Object -First 1
}

if (-not $selected) {
    $selected = $healthy | Select-Object -First 1
}

if (-not $selected) {
    throw "No healthy bridge playlist found. Run init-ncm-bridge-playlist.ps1 first."
}

$beforeActive = $config.activePlaylistKey
$removedKeys = @()

if ($PruneMissing) {
    foreach ($item in @($items | Where-Object { $_.status -ne "ok" })) {
        $config.bridgePlaylists.PSObject.Properties.Remove($item.playlistKey)
        $removedKeys += $item.playlistKey
    }
}

$config.activePlaylistKey = $selected.playlistKey

if (-not $DryRun) {
    Write-BridgeConfig -Path $ConfigPath -Config $config
}

$result = [pscustomobject]@{
    success = $true
    action = "repair"
    code = "OK"
    message = if ($DryRun) { "Bridge config repair previewed." } else { "Bridge config repaired." }
    dryRun = [bool]$DryRun
    configPath = $ConfigPath
    beforeActivePlaylistKey = $beforeActive
    activePlaylistKey = $config.activePlaylistKey
    healthyKeys = @($healthy | ForEach-Object { $_.playlistKey })
    missingKeys = @($items | Where-Object { $_.status -ne "ok" } | ForEach-Object { $_.playlistKey })
    removedKeys = $removedKeys
}

if ($outputJson) {
    $result | ConvertTo-Json -Depth 6
    exit
}

if ($DryRun) {
    "Bridge config repair previewed."
}
else {
    "Bridge config repaired."
}
"Active key: $beforeActive -> $($config.activePlaylistKey)"
if ($removedKeys.Count -gt 0) {
    "Removed missing keys: $($removedKeys -join ', ')"
}
