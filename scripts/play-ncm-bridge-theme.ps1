param(
    [Parameter(Mandatory = $true)]
    [string]$Theme,

    [Parameter(Mandatory = $true)]
    [string[]]$SongIds,

    [string]$Description = "",
    [string]$RoleName = "",
    [string]$PlaylistKey = "default",
    [string]$ConfigPath = $null,
    [switch]$NoReplace,
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$outputJson = [bool]$Json

. (Join-Path $PSScriptRoot "NcmBridge.Config.ps1")

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

$themeScript = Join-Path $PSScriptRoot "set-ncm-bridge-theme.ps1"
$replaceScript = Join-Path $PSScriptRoot "replace-ncm-bridge-tracks.ps1"
$orpheusScript = Join-Path $repoRoot "netease-music-cli\OrpheusControl.ps1"

$themeArgs = @("-ExecutionPolicy", "Bypass", "-File", $themeScript, "-Theme", $Theme, "-PlaylistKey", $playlistKeyValue, "-ConfigPath", $ConfigPath, "-Json")
if (-not [string]::IsNullOrWhiteSpace($Description)) { $themeArgs += @("-Description", $Description) }
if (-not [string]::IsNullOrWhiteSpace($RoleName)) { $themeArgs += @("-RoleName", $RoleName) }

$themeRaw = & powershell @themeArgs
if ($LASTEXITCODE -ne 0) { throw "set-ncm-bridge-theme.ps1 failed." }
$themeResult = ($themeRaw -join "`n") | ConvertFrom-Json -ErrorAction Stop

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

$replaceResult = $null
if (-not $NoReplace) {
    $replaceRaw = & $replaceScript -SongIds $targetSongIds -PlaylistKey $playlistKeyValue -ConfigPath $ConfigPath -Json
    $replaceResult = ($replaceRaw -join "`n") | ConvertFrom-Json -ErrorAction Stop
}

$config = Read-BridgeConfig -Path $ConfigPath
$entry = Get-BridgePlaylistEntry -Config $config -Key $playlistKeyValue
if (-not $entry -or -not $entry.originalId) {
    throw "Bridge playlist '$playlistKeyValue' does not contain originalId. Run init-ncm-bridge-playlist.ps1 first."
}

. $orpheusScript
if ($DryRun) {
    $playUrl = Invoke-OrpheusCommand -Name "play_playlist" -Params @{ id = "$($entry.originalId)" } -DryRun 6>$null
}
else {
    $playUrl = Invoke-OrpheusCommand -Name "play_playlist" -Params @{ id = "$($entry.originalId)" } 6>$null
}

$result = [pscustomobject]@{
    success = $true
    action = "playTheme"
    code = if ($DryRun) { "URL_PREVIEWED" } else { "URL_LAUNCHED" }
    message = if ($DryRun) { "Protocol URL previewed. Dry-run does not verify playback." } else { "Protocol URL launched. Use SMTC to verify playback." }
    dryRun = [bool]$DryRun
    verified = $false
    configPath = $ConfigPath
    playlistKey = $playlistKeyValue
    theme = $themeResult
    replace = $replaceResult
    playUrl = $playUrl
}

if ($outputJson) {
    $result | ConvertTo-Json -Depth 10
    exit
}

"Bridge playlist theme prepared: $($entry.displayName)"
"Playlist key: $playlistKeyValue"
if ($replaceResult) { "Tracks replaced: removed $($replaceResult.removedCount), added $($replaceResult.addedCount)" }
if ($DryRun) { "DryRun play URL: $playUrl" } else { "Play command sent: $playUrl" }
