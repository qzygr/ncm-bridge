param(
    [Parameter(Mandatory = $true)]
    [string]$Theme,

    [string]$Description = "",
    [string]$RoleName = "",
    [string]$PlaylistKey = "default",
    [string]$ConfigPath = $null,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$outputJson = [bool]$Json

. (Join-Path $PSScriptRoot "NcmBridge.Cli.ps1")
. (Join-Path $PSScriptRoot "NcmBridge.Config.ps1")
. (Join-Path $PSScriptRoot "NcmBridge.Text.ps1")
. (Join-Path $PSScriptRoot "NcmBridge.Playlist.ps1")

if (-not $ConfigPath) {
    $ConfigPath = Get-NcmBridgeDefaultConfigPath
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
    throw "Bridge playlist '$playlistKeyValue' is missing from created playlists. Re-run init-ncm-bridge-playlist.ps1 for this PlaylistKey before updating it."
}

$roleValue = if ([string]::IsNullOrWhiteSpace($RoleName)) {
    if ($entry.roleName) { "$($entry.roleName)" } else { "Agent" }
}
else {
    $RoleName.Trim()
}

$displayName = Get-BridgePlaylistName -Title $Theme -RoleName $roleValue
$displayNameWidth = Get-NcmTextWidth -Text $displayName
if ($displayNameWidth -gt 40) {
    throw "Playlist name is too long: width $displayNameWidth, maximum 40. Half-width characters count as 1, full-width characters count as 2."
}

$descriptionValue = $Description.Trim()
$descriptionWidth = 0
if (-not [string]::IsNullOrWhiteSpace($descriptionValue)) {
    $descriptionWidth = Get-NcmTextWidth -Text $descriptionValue
    if ($descriptionWidth -gt 80) {
        throw "Playlist description is too long: width $descriptionWidth, maximum 80. Half-width characters count as 1, full-width characters count as 2."
    }
}

$response = Invoke-NcmCliJson -Arguments @("playlist", "updateName", "--playlistId", "$($entry.encryptedId)", "--name", $displayName, "--output", "json")
Assert-NcmCliOk -Response $response -Message "Failed to update playlist name"

if (-not [string]::IsNullOrWhiteSpace($descriptionValue)) {
    $descResponse = Invoke-NcmCliJson -Arguments @("playlist", "updateDesc", "--playlistId", "$($entry.encryptedId)", "--desc", $descriptionValue, "--output", "json")
    Assert-NcmCliOk -Response $descResponse -Message "Failed to update playlist description"
}

$entry | Add-Member -NotePropertyName key -NotePropertyValue $playlistKeyValue -Force
$entry | Add-Member -NotePropertyName baseName -NotePropertyValue "ncm-bridge" -Force
$entry | Add-Member -NotePropertyName roleName -NotePropertyValue $roleValue -Force
$entry | Add-Member -NotePropertyName theme -NotePropertyValue $Theme.Trim() -Force
$entry | Add-Member -NotePropertyName displayName -NotePropertyValue $displayName -Force
$entry | Add-Member -NotePropertyName description -NotePropertyValue $descriptionValue -Force
$entry | Add-Member -NotePropertyName updatedAt -NotePropertyValue ([DateTimeOffset]::Now.ToString("o")) -Force

Set-BridgePlaylistEntry -Config $config -Key $playlistKeyValue -Playlist $entry
Write-BridgeConfig -Path $ConfigPath -Config $config

$result = [pscustomobject]@{
    success = $true
    action = "renamed"
    code = "OK"
    message = "Bridge playlist renamed."
    configPath = $ConfigPath
    playlistKey = $playlistKeyValue
    displayNameWidth = $displayNameWidth
    descriptionWidth = $descriptionWidth
    bridgePlaylist = $entry
}

if ($outputJson) {
    $result | ConvertTo-Json -Depth 10
    exit
}

"Bridge playlist renamed: $displayName"
"Playlist key: $playlistKeyValue"
"Encrypted ID: $($entry.encryptedId)"
"Config: $ConfigPath"
