<#
主要作用：初始化、复用或修复一个程序专用歌单及其本地绑定。
输入：基础名称、角色名、PlaylistKey、配置路径和 JSON 开关。
输出：创建、复用、重命名或加载结果，以及更新后的绑定信息。
#>

param(
    [string]$BaseName = "ncm-bridge",
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

$displayName = Get-BridgePlaylistName -Title $BaseName -RoleName $RoleName
$config = Read-BridgeConfig -Path $ConfigPath -AllowMissing
$entry = Get-BridgePlaylistEntry -Config $config -Key $playlistKeyValue
$action = $null
$playlist = $null

if ($entry -and $entry.encryptedId) {
    $playlist = Find-CreatedPlaylistByIds -EncryptedId "$($entry.encryptedId)" -OriginalId "$($entry.originalId)"
    if (-not $playlist) {
        $playlist = Find-CreatedPlaylistByName -Name $displayName
        if ($playlist) {
            $action = "reused"
        }
        else {
            $playlist = New-BridgePlaylist -Name $displayName
            $action = "created"
        }
    }
    else {
        $playlist = Get-PlaylistDetail -EncryptedId $playlist.id
    }

    if ($playlist.name -ne $displayName) {
        Rename-Playlist -EncryptedId $playlist.id -Name $displayName
        $playlist = Get-PlaylistDetail -EncryptedId $playlist.id
        $action = "renamed"
    }
    elseif (-not $action) {
        $action = "loaded"
    }
}
else {
    $playlist = Find-CreatedPlaylistByName -Name $displayName
    if ($playlist) {
        $action = "reused"
    }
    else {
        $playlist = New-BridgePlaylist -Name $displayName
        $action = "created"
    }
}

$roleValue = if ([string]::IsNullOrWhiteSpace($RoleName)) { "Agent" } else { $RoleName.Trim() }
$playlistEntry = [pscustomobject]@{
    key = $playlistKeyValue
    baseName = $BaseName.Trim()
    roleName = $roleValue
    displayName = $displayName
    originalId = "$($playlist.originalId)"
    encryptedId = "$($playlist.id)"
    updatedAt = [DateTimeOffset]::Now.ToString("o")
}

Set-BridgePlaylistEntry -Config $config -Key $playlistKeyValue -Playlist $playlistEntry
Write-BridgeConfig -Path $ConfigPath -Config $config

$result = [pscustomobject]@{
    success = $true
    action = $action
    code = "OK"
    message = "Bridge playlist $action."
    configPath = $ConfigPath
    playlistKey = $playlistKeyValue
    bridgePlaylist = $playlistEntry
}

if ($outputJson) {
    $result | ConvertTo-Json -Depth 10
    exit
}

"Bridge playlist ${action}: $displayName"
"Playlist key: $playlistKeyValue"
"Original ID: $($playlistEntry.originalId)"
"Encrypted ID: $($playlistEntry.encryptedId)"
"Config: $ConfigPath"
