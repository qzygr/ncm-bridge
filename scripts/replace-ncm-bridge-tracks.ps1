param(
    [Parameter(Mandatory = $true)]
    [string[]]$SongIds,

    [string]$PlaylistKey = "default",
    [string]$ConfigPath = $null,
    [switch]$ValidateOnly,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$outputJson = [bool]$Json

. (Join-Path $PSScriptRoot "NcmBridge.Cli.ps1")
. (Join-Path $PSScriptRoot "NcmBridge.Config.ps1")
. (Join-Path $PSScriptRoot "NcmBridge.Playlist.ps1")

if (-not $ConfigPath) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $ConfigPath = Join-Path $repoRoot ".ncm-bridge.json"
}
else {
    $repoRoot = Split-Path -Parent $PSScriptRoot
}

$playlistKeyValue = $PlaylistKey.Trim()
if ([string]::IsNullOrWhiteSpace($playlistKeyValue)) {
    throw "PlaylistKey cannot be empty."
}

$config = Read-BridgeConfig -Path $ConfigPath
$entry = Get-BridgePlaylistEntry -Config $config -Key $playlistKeyValue
if (-not $entry -or -not $entry.encryptedId) {
    throw "Bridge playlist '$playlistKeyValue' not found. Run init-ncm-bridge-playlist.ps1 with -PlaylistKey '$playlistKeyValue' first."
}

if (-not (Test-BridgePlaylistIsCreated -Playlist $entry)) {
    throw "Bridge playlist '$playlistKeyValue' is missing from created playlists. Re-run init-ncm-bridge-playlist.ps1 for this PlaylistKey before replacing tracks."
}

$playlistId = "$($entry.encryptedId)"
$targetSongIds = @(
    $SongIds |
        ForEach-Object { "$_".Split(",") } |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
)
if ($targetSongIds.Count -eq 0) {
    throw "At least one encrypted song ID is required."
}

$invalidSongIds = @($targetSongIds | Where-Object { $_ -notmatch '^[0-9A-Fa-f]{32}$' })
if ($invalidSongIds.Count -gt 0) {
    throw "SongIds must be encrypted 32-character hex IDs. Invalid: $($invalidSongIds -join ', ')"
}

$tracksResponse = Invoke-NcmCliJson -Arguments @("playlist", "tracks", "--playlistId", $playlistId, "--limit", "500", "--offset", "0", "--output", "json")
Assert-NcmCliOk -Response $tracksResponse -Message "Failed to read playlist tracks"

$existingSongIds = @($tracksResponse.data | ForEach-Object { "$($_.id)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$removed = @()
$added = @()

if ($ValidateOnly) {
    $result = [pscustomobject]@{
        success = $true
        action = "validateReplaceTracks"
        code = "OK"
        message = "Bridge playlist track replacement validated."
        configPath = $ConfigPath
        playlistKey = $playlistKeyValue
        playlistId = $playlistId
        existingCount = $existingSongIds.Count
        targetCount = $targetSongIds.Count
        targetSongIds = $targetSongIds
    }

    if ($outputJson) {
        $result | ConvertTo-Json -Depth 8
        exit
    }

    "Bridge playlist track replacement validated."
    "Playlist key: $playlistKeyValue"
    "Existing: $($existingSongIds.Count)"
    "Target: $($targetSongIds.Count)"
    exit
}

if ($existingSongIds.Count -gt 0) {
    $null = Invoke-NcmPlaylistControl -Action remove -PlaylistId $playlistId -SongIds $existingSongIds
    $removed = $existingSongIds
}

$null = Invoke-NcmPlaylistControl -Action add -PlaylistId $playlistId -SongIds $targetSongIds
$added = $targetSongIds

$result = [pscustomobject]@{
    success = $true
    action = "replaceTracks"
    code = "OK"
    message = "Bridge playlist tracks replaced."
    configPath = $ConfigPath
    playlistKey = $playlistKeyValue
    playlistId = $playlistId
    removedCount = $removed.Count
    addedCount = $added.Count
    removedSongIds = $removed
    addedSongIds = $added
}

if ($outputJson) {
    $result | ConvertTo-Json -Depth 8
    exit
}

"Bridge playlist tracks replaced."
"Playlist key: $playlistKeyValue"
"Removed: $($removed.Count)"
"Added: $($added.Count)"
"Playlist ID: $playlistId"
