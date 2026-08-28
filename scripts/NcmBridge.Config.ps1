<#
主要作用：管理 ncm-bridge 的本地歌单绑定配置。
输入：配置文件路径、歌单 key 与歌单条目对象。
输出：配置对象、指定条目或写入后的本地 JSON 文件。
#>

$ErrorActionPreference = "Stop"

<#
主要作用：返回仓库默认的本地配置文件路径。
输入：无。
输出：.ncm-bridge.json 的绝对路径。
#>
function Get-NcmBridgeDefaultConfigPath {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Join-Path $repoRoot ".ncm-bridge.json"
}

<#
主要作用：读取并校验本地歌单绑定配置。
输入：配置文件路径，以及是否允许配置文件不存在。
输出：规范化的配置对象；格式错误时抛出异常。
#>
function Read-BridgeConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowMissing
    )

    if (-not (Test-Path $Path)) {
        if ($AllowMissing) {
            return [pscustomobject]@{
                activePlaylistKey = $null
                bridgePlaylists = [pscustomobject]@{}
            }
        }

        throw "Bridge config not found: $Path. Run init-ncm-bridge-playlist.ps1 first."
    }

    $config = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if (-not $config.bridgePlaylists) {
        $playlists = [pscustomobject]@{}
        if ($config.bridgePlaylist) {
            $playlists | Add-Member -NotePropertyName "default" -NotePropertyValue $config.bridgePlaylist -Force
        }
        $config = [pscustomobject]@{
            activePlaylistKey = if ($config.bridgePlaylist) { "default" } else { $null }
            bridgePlaylists = $playlists
        }
    }
    elseif (-not $config.activePlaylistKey) {
        $config | Add-Member -NotePropertyName activePlaylistKey -NotePropertyValue $null -Force
    }

    $config
}

<#
主要作用：将歌单绑定配置持久化为 UTF-8 JSON。
输入：目标路径与待保存的配置对象。
输出：写入后的配置对象。
#>
function Write-BridgeConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Config
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory | Out-Null
    }

    $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

<#
主要作用：按 key 查找配置中的程序专用歌单条目。
输入：配置对象与 PlaylistKey。
输出：匹配的歌单条目；未找到时返回 null。
#>
function Get-BridgePlaylistEntry {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $property = $Config.bridgePlaylists.PSObject.Properties[$Key]
    if ($property) { return $property.Value }
    return $null
}

<#
主要作用：新增或更新指定 key 的歌单绑定。
输入：配置对象、PlaylistKey 与完整歌单条目。
输出：更新后的配置对象。
#>
function Set-BridgePlaylistEntry {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][object]$Playlist
    )

    $Config.bridgePlaylists | Add-Member -NotePropertyName $Key -NotePropertyValue $Playlist -Force
    $Config.activePlaylistKey = $Key
}

<#
主要作用：列出配置中全部程序专用歌单 key。
输入：配置对象。
输出：按配置保存的 key 字符串数组。
#>
function Get-BridgePlaylistKeys {
    param([Parameter(Mandatory = $true)][object]$Config)

    @($Config.bridgePlaylists.PSObject.Properties.Name)
}
