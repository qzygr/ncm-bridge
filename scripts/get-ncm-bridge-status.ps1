param(
    [string]$PlaylistKey = "",
    [string]$ConfigPath = $null,
    [switch]$All,
    [switch]$Summary,
    [switch]$IncludeConfig,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$outputJson = [bool]$Json

. (Join-Path $PSScriptRoot "NcmBridge.Cli.ps1")
. (Join-Path $PSScriptRoot "NcmBridge.Config.ps1")
. (Join-Path $PSScriptRoot "NcmBridge.Playlist.ps1")

function New-StatusItem {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object]$Entry,
        [object]$Remote
    )

    if (-not $Entry) {
        return [pscustomobject]@{
            playlistKey = $Key
            status = "missing"
            reason = "not_in_config"
            trackCount = $null
            name = $null
            configured = $null
            remote = $null
        }
    }

    if ($Remote) {
        return [pscustomobject]@{
            playlistKey = $Key
            status = "ok"
            reason = $null
            trackCount = $Remote.trackCount
            name = $Remote.name
            configured = if ($IncludeConfig) { $Entry } else { $null }
            remote = [pscustomobject]@{
                originalId = "$($Remote.originalId)"
                encryptedId = "$($Remote.id)"
                name = $Remote.name
                describe = $Remote.describe
                trackCount = $Remote.trackCount
            }
        }
    }

    [pscustomobject]@{
        playlistKey = $Key
        status = "missing"
        reason = "not_in_created_playlists"
        trackCount = $null
        name = $null
        configured = if ($IncludeConfig) { $Entry } else { $null }
        remote = $null
    }
}

if (-not $ConfigPath) {
    $ConfigPath = Get-NcmBridgeDefaultConfigPath
}

$config = Read-BridgeConfig -Path $ConfigPath
$createdPlaylists = Get-CreatedPlaylists

if ($All) {
    $keys = Get-BridgePlaylistKeys -Config $config
}
elseif ([string]::IsNullOrWhiteSpace($PlaylistKey)) {
    if ($config.activePlaylistKey) {
        $keys = @("$($config.activePlaylistKey)")
    }
    else {
        $keys = Get-BridgePlaylistKeys -Config $config
    }
}
else {
    $keys = @($PlaylistKey.Trim())
}

$items = foreach ($key in $keys) {
    $entry = Get-BridgePlaylistEntry -Config $config -Key $key
    $remote = if ($entry) { Find-CreatedPlaylistByEntry -CreatedPlaylists $createdPlaylists -Entry $entry } else { $null }
    New-StatusItem -Key $key -Entry $entry -Remote $remote
}

if ($Summary -and -not $All -and @($items).Count -eq 1) {
    $item = @($items)[0]
    $result = [pscustomobject]@{
        success = $true
        action = "status"
        code = if ($item.status -eq "ok") { "OK" } else { "MISSING" }
        message = if ($item.status -eq "ok") { "Bridge playlist is healthy." } else { "Bridge playlist is missing." }
        activePlaylistKey = $config.activePlaylistKey
        playlistKey = $item.playlistKey
        status = $item.status
        reason = $item.reason
        trackCount = $item.trackCount
        name = $item.name
    }
}
else {
    $result = [pscustomobject]@{
        success = $true
        action = "status"
        code = "OK"
        message = "Bridge playlist status loaded."
        configPath = $ConfigPath
        activePlaylistKey = $config.activePlaylistKey
        createdPlaylistCount = $createdPlaylists.Count
        playlists = @($items)
    }
}

if ($outputJson) {
    $depth = if ($IncludeConfig) { 10 } else { 6 }
    $result | ConvertTo-Json -Depth $depth
    exit
}

if ($Summary -and -not $All -and $result.PSObject.Properties["status"]) {
    "[$($result.status)] $($result.playlistKey): $($result.name)"
    exit
}

foreach ($item in $result.playlists) {
    if ($item.status -eq "ok") {
        "[$($item.status)] $($item.playlistKey): $($item.name) ($($item.trackCount) tracks)"
    }
    else {
        "[$($item.status)] $($item.playlistKey): $($item.reason)"
    }
}
