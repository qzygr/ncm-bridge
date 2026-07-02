$ErrorActionPreference = "Stop"

function Get-NcmBridgeDefaultConfigPath {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Join-Path $repoRoot ".ncm-bridge.json"
}

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

function Get-BridgePlaylistEntry {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $property = $Config.bridgePlaylists.PSObject.Properties[$Key]
    if ($property) { return $property.Value }
    return $null
}

function Set-BridgePlaylistEntry {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][object]$Playlist
    )

    $Config.bridgePlaylists | Add-Member -NotePropertyName $Key -NotePropertyValue $Playlist -Force
    $Config.activePlaylistKey = $Key
}

function Get-BridgePlaylistKeys {
    param([Parameter(Mandatory = $true)][object]$Config)

    @($Config.bridgePlaylists.PSObject.Properties.Name)
}
