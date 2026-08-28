<#
主要作用：查询本地绑定的程序专用歌单是否能在远端健康解析。
输入：PlaylistKey、配置路径、是否查看全部/摘要/配置细节及 JSON 开关。
输出：单个或多个歌单的健康状态、名称、曲目数与可选配置数据。
#>

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

$scriptsRoot = Split-Path -Parent $PSScriptRoot
$modulesRoot = Join-Path $scriptsRoot "modules"
. (Join-Path $modulesRoot "NcmBridge.Cli.ps1")
. (Join-Path $modulesRoot "NcmBridge.Config.ps1")
. (Join-Path $modulesRoot "NcmBridge.Playlist.ps1")

<#
主要作用：将本地绑定条目和远端查询结果整理为统一状态项。
输入：PlaylistKey、本地条目和可选远端歌单对象。
输出：包含 ok、missing 或原因字段的状态对象。
#>
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
