<#
主要作用：校验并替换程序专用歌单的远端曲目列表。
输入：加密歌曲 ID、PlaylistKey、配置路径、ValidateOnly 与 JSON 开关。
输出：曲目校验结果或远端替换操作结果。
#>

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

$scriptsRoot = Split-Path -Parent $PSScriptRoot
$modulesRoot = Join-Path $scriptsRoot "modules"
. (Join-Path $modulesRoot "NcmBridge.Cli.ps1")
. (Join-Path $modulesRoot "NcmBridge.Config.ps1")
. (Join-Path $modulesRoot "NcmBridge.Playlist.ps1")

if (-not $ConfigPath) {
    $repoRoot = Split-Path -Parent $scriptsRoot
    $ConfigPath = Join-Path $repoRoot ".ncm-bridge.json"
}
else {
    $repoRoot = Split-Path -Parent $scriptsRoot
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

$insertSongIds = ConvertTo-NcmBridgeInsertOrder -SongIds $targetSongIds

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
        insertSongIds = $insertSongIds
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
    $removeResponse = Invoke-NcmPlaylistControl -Action remove -PlaylistId $playlistId -SongIds $existingSongIds
    Assert-NcmCliOk -Response $removeResponse -Message "Failed to remove existing playlist tracks"
    $removed = $existingSongIds
}

$addResponse = Invoke-NcmPlaylistControl -Action add -PlaylistId $playlistId -SongIds $insertSongIds
Assert-NcmCliOk -Response $addResponse -Message "Failed to add replacement playlist tracks"
$added = $insertSongIds

$finalTracksResponse = Invoke-NcmCliJson -Arguments @("playlist", "tracks", "--playlistId", $playlistId, "--limit", "500", "--offset", "0", "--output", "json")
Assert-NcmCliOk -Response $finalTracksResponse -Message "Failed to verify replacement playlist tracks"
$finalSongIds = @($finalTracksResponse.data | ForEach-Object { "$($_.id)" })
if (($finalSongIds -join ",") -ne ($targetSongIds -join ",")) {
    throw "Playlist replacement verification failed. Expected order: $($targetSongIds -join ','); actual order: $($finalSongIds -join ',')"
}

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
    verified = $true
    requestedSongIds = $targetSongIds
    insertedSongIds = $insertSongIds
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
