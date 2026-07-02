param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("status", "repair", "pruneMissing", "dryRun", "searchSong", "playSong", "verifyPlayback", "playDefault", "setTheme", "replaceTracks", "validateReplaceTracks", "playTheme")]
    [string]$Action,

    [string]$Keyword = "",
    [string]$OriginalId = "",
    [string]$ExpectedTitle = "",
    [string]$ExpectedArtist = "",
    [string]$Artist = "",
    [string]$ExactTitle = "",
    [string]$Theme = "",
    [string]$Description = "",
    [string[]]$SongIds = @(),
    [string]$PlaylistKey = "default",
    [string]$ConfigPath = $null,
    [string]$Prefer = "",
    [int]$Limit = 5,
    [int]$Attempts = 8,
    [int]$RetryDelayMs = 700,
    [int]$InitialDelayMs = 500,
    [switch]$PruneMissing,
    [switch]$Verify,
    [switch]$DryRun,
    [switch]$Json,
    [switch]$CompressJson
)

$ErrorActionPreference = "Stop"
$outputJson = [bool]$Json
$verifyAttempts = $Attempts
$verifyRetryDelayMs = $RetryDelayMs
$verifyInitialDelayMs = $InitialDelayMs

. (Join-Path $PSScriptRoot "NcmBridge.Config.ps1")
. (Join-Path $PSScriptRoot "NcmBridge.Cli.ps1")
. (Join-Path $PSScriptRoot "NcmBridge.Text.ps1")

if (-not $ConfigPath) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $ConfigPath = Join-Path $repoRoot ".ncm-bridge.json"
}
else {
    $repoRoot = Split-Path -Parent $PSScriptRoot
}

function Write-BridgeResult {
    param([Parameter(Mandatory = $true)][object]$Value)

    if ($outputJson) {
        $Value | ConvertTo-Json -Depth 10 -Compress:$CompressJson
        exit
    }

    if ($Value.message) { $Value.message }
    else { $Value | ConvertTo-Json -Depth 6 }
}

function Invoke-BridgeScript {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $raw = & powershell @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Bridge action failed: $($Arguments -join ' ')"
    }

    $text = $raw -join "`n"
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $text | ConvertFrom-Json -ErrorAction Stop
}

function Get-TargetSongIds {
    $ids = @(
        $SongIds |
            ForEach-Object { "$_".Split(",") } |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    if ($ids.Count -eq 0) {
        throw "SongIds are required for action '$Action'."
    }

    $ids
}

function Test-TextMatch {
    param(
        [string]$Actual,
        [string]$Expected
    )

    if ([string]::IsNullOrWhiteSpace($Expected)) { return $true }
    if ([string]::IsNullOrWhiteSpace($Actual)) { return $false }
    return $Actual.IndexOf($Expected, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Invoke-PlaybackVerification {
    param(
        [string]$ExpectedTitle = "",
        [string]$ExpectedArtist = ""
    )

    . (Join-Path $repoRoot "netease-music-cli\OrpheusControl.ps1")
    if ($verifyAttempts -lt 1) { $verifyAttempts = 1 }
    if ($verifyRetryDelayMs -lt 0) { $verifyRetryDelayMs = 0 }
    if ($verifyInitialDelayMs -lt 0) { $verifyInitialDelayMs = 0 }

    if ($verifyInitialDelayMs -gt 0) {
        Start-Sleep -Milliseconds $verifyInitialDelayMs
    }

    $status = $null
    $titleMatched = $false
    $artistMatched = $false
    $playingMatched = $false
    $verified = $false
    $matchedAttempt = $null

    for ($attempt = 1; $attempt -le $verifyAttempts; $attempt++) {
        $status = Get-NeteasePlaybackStatus -Attempts 1 -RetryDelayMs 0 -InitialDelayMs 0
        $titleMatched = Test-TextMatch -Actual "$($status.Title)" -Expected $ExpectedTitle
        $artistMatched = Test-TextMatch -Actual "$($status.Artist)" -Expected $ExpectedArtist
        $playingMatched = "$($status.PlaybackStatus)" -eq "Playing"
        $verified = [bool]($status.Success -and $titleMatched -and $artistMatched -and $playingMatched)

        if ($status) {
            $status | Add-Member -NotePropertyName VerifyAttempt -NotePropertyValue $attempt -Force
            $status | Add-Member -NotePropertyName VerifyAttempts -NotePropertyValue $verifyAttempts -Force
        }

        if ($verified) {
            $matchedAttempt = $attempt
            break
        }

        if ($attempt -lt $verifyAttempts -and $verifyRetryDelayMs -gt 0) {
            Start-Sleep -Milliseconds $verifyRetryDelayMs
        }
    }

    [pscustomobject]@{
        success = $verified
        action = "verifyPlayback"
        code = if ($verified) { "VERIFIED" } else { "NOT_VERIFIED" }
        message = if ($verified) { "Playback verified by SMTC." } else { "Playback was not verified by SMTC." }
        expectedTitle = $ExpectedTitle
        expectedArtist = $ExpectedArtist
        titleMatched = $titleMatched
        artistMatched = $artistMatched
        playingMatched = $playingMatched
        matchedAttempt = $matchedAttempt
        attempts = $verifyAttempts
        retryDelayMs = $verifyRetryDelayMs
        initialDelayMs = $verifyInitialDelayMs
        smtc = $status
    }
}

function Get-BridgeThemePreview {
    param(
        [Parameter(Mandatory = $true)][string]$ThemeValue,
        [string]$DescriptionValue = ""
    )

    if ([string]::IsNullOrWhiteSpace($ThemeValue)) { throw "Theme is required." }

    $config = Read-BridgeConfig -Path $ConfigPath
    $key = if ([string]::IsNullOrWhiteSpace($PlaylistKey)) { "$($config.activePlaylistKey)" } else { $PlaylistKey.Trim() }
    $entry = Get-BridgePlaylistEntry -Config $config -Key $key
    if (-not $entry) { throw "Bridge playlist '$key' not found." }

    $roleValue = if ($entry.roleName) { "$($entry.roleName)" } else { "Agent" }
    $displayName = Get-BridgePlaylistName -Title $ThemeValue -RoleName $roleValue
    $descriptionValue = $DescriptionValue.Trim()

    [pscustomobject]@{
        success = $true
        action = "previewSetTheme"
        code = "DRY_RUN"
        message = "Bridge playlist theme update previewed. No remote write was performed."
        dryRun = $true
        playlistKey = $key
        displayName = $displayName
        displayNameWidth = Get-NcmTextWidth -Text $displayName
        description = $descriptionValue
        descriptionWidth = if ([string]::IsNullOrWhiteSpace($descriptionValue)) { 0 } else { Get-NcmTextWidth -Text $descriptionValue }
    }
}

$result = switch ($Action) {
    "status" {
        $args = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "get-ncm-bridge-status.ps1"), "-PlaylistKey", $PlaylistKey, "-ConfigPath", $ConfigPath, "-Summary", "-Json")
        Invoke-BridgeScript -Arguments $args
    }

    "repair" {
        $args = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "repair-ncm-bridge-config.ps1"), "-ConfigPath", $ConfigPath, "-Json")
        if (-not [string]::IsNullOrWhiteSpace($Prefer)) { $args += @("-Prefer", $Prefer) }
        if ($PruneMissing) { $args += "-PruneMissing" }
        if ($DryRun) { $args += "-DryRun" }
        Invoke-BridgeScript -Arguments $args
    }

    "pruneMissing" {
        $args = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "repair-ncm-bridge-config.ps1"), "-ConfigPath", $ConfigPath, "-PruneMissing", "-Json")
        if (-not [string]::IsNullOrWhiteSpace($Prefer)) { $args += @("-Prefer", $Prefer) }
        if ($DryRun) { $args += "-DryRun" }
        Invoke-BridgeScript -Arguments $args
    }

    "dryRun" {
        $args = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "test-orpheus-payload.ps1"), "-Json")
        Invoke-BridgeScript -Arguments $args
    }

    "searchSong" {
        if ([string]::IsNullOrWhiteSpace($Keyword)) { throw "Keyword is required for action 'searchSong'." }
        if ($Limit -lt 1) { $Limit = 1 }
        if ($Limit -gt 20) { $Limit = 20 }

        $response = Invoke-NcmCliJson -Arguments @("search", "song", "--keyword", $Keyword, "--userInput", "搜索 $Keyword", "--limit", "$Limit", "--output", "json")
        Assert-NcmCliOk -Response $response -Message "Failed to search songs"
        $records = @($response.data.records)
        if (-not [string]::IsNullOrWhiteSpace($ExactTitle)) {
            $records = @($records | Where-Object { "$($_.name)" -eq $ExactTitle })
        }
        if (-not [string]::IsNullOrWhiteSpace($Artist)) {
            $records = @($records | Where-Object {
                $artistNames = @($_.artists | ForEach-Object { "$($_.name)" })
                @($artistNames | Where-Object { $_.IndexOf($Artist, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0
            })
        }
        $records = @($records | Select-Object -First $Limit)
        $items = foreach ($record in $records) {
            [pscustomobject]@{
                name = $record.name
                artists = @($record.artists | ForEach-Object { $_.name })
                originalId = "$($record.originalId)"
                encryptedId = "$($record.id)"
                album = $record.album.name
                duration = $record.duration
            }
        }

        [pscustomobject]@{
            success = $true
            action = "searchSong"
            code = "OK"
            message = "Song search completed."
            keyword = $Keyword
            artist = $Artist
            exactTitle = $ExactTitle
            count = @($items).Count
            records = @($items)
        }
    }

    "verifyPlayback" {
        Invoke-PlaybackVerification -ExpectedTitle $ExpectedTitle -ExpectedArtist $ExpectedArtist
    }

    "playSong" {
        if ([string]::IsNullOrWhiteSpace($OriginalId)) { throw "OriginalId is required for action 'playSong'." }

        . (Join-Path $repoRoot "netease-music-cli\OrpheusControl.ps1")
        $url = Invoke-OrpheusCommand -Name "play_song" -Params @{ id = "$OriginalId" } -DryRun:$DryRun 6>$null
        $verification = if ($Verify -and -not $DryRun) {
            Invoke-PlaybackVerification -ExpectedTitle $ExpectedTitle -ExpectedArtist $ExpectedArtist
        }
        else {
            $null
        }

        [pscustomobject]@{
            success = if ($verification) { [bool]$verification.success } else { $true }
            action = "playSong"
            code = if ($DryRun) { "URL_PREVIEWED" } elseif ($verification -and $verification.success) { "VERIFIED" } else { "URL_LAUNCHED" }
            message = if ($verification -and $verification.success) { "Playback verified by SMTC." } elseif ($DryRun) { "Protocol URL previewed. Dry-run does not verify playback." } else { "Protocol URL launched. Use SMTC to verify playback." }
            dryRun = [bool]$DryRun
            verified = if ($verification) { [bool]$verification.success } else { $false }
            originalId = "$OriginalId"
            playUrl = $url
            verification = $verification
        }
    }

    "playDefault" {
        $config = Read-BridgeConfig -Path $ConfigPath
        $key = if ([string]::IsNullOrWhiteSpace($PlaylistKey)) { "$($config.activePlaylistKey)" } else { $PlaylistKey.Trim() }
        $entry = Get-BridgePlaylistEntry -Config $config -Key $key
        if (-not $entry -or -not $entry.originalId) {
            throw "Bridge playlist '$key' does not contain originalId. Run init first."
        }

        . (Join-Path $repoRoot "netease-music-cli\OrpheusControl.ps1")
        $url = Invoke-OrpheusCommand -Name "play_playlist" -Params @{ id = "$($entry.originalId)" } -DryRun:$DryRun 6>$null
        [pscustomobject]@{
            success = $true
            action = "playDefault"
            code = if ($DryRun) { "URL_PREVIEWED" } else { "URL_LAUNCHED" }
            message = if ($DryRun) { "Protocol URL previewed. Dry-run does not verify playback." } else { "Protocol URL launched. Use SMTC to verify playback." }
            dryRun = [bool]$DryRun
            verified = $false
            playlistKey = $key
            originalId = "$($entry.originalId)"
            playUrl = $url
        }
    }

    "setTheme" {
        if ([string]::IsNullOrWhiteSpace($Theme)) { throw "Theme is required for action 'setTheme'." }
        if ($DryRun) {
            Get-BridgeThemePreview -ThemeValue $Theme -DescriptionValue $Description
            break
        }

        $args = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "set-ncm-bridge-theme.ps1"), "-Theme", $Theme, "-PlaylistKey", $PlaylistKey, "-ConfigPath", $ConfigPath, "-Json")
        if (-not [string]::IsNullOrWhiteSpace($Description)) { $args += @("-Description", $Description) }
        Invoke-BridgeScript -Arguments $args
    }

    "replaceTracks" {
        $ids = Get-TargetSongIds
        $args = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "replace-ncm-bridge-tracks.ps1"), "-SongIds", ($ids -join ","), "-PlaylistKey", $PlaylistKey, "-ConfigPath", $ConfigPath, "-Json")
        if ($DryRun) { $args += "-ValidateOnly" }
        Invoke-BridgeScript -Arguments $args
    }

    "validateReplaceTracks" {
        $ids = Get-TargetSongIds
        $args = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "replace-ncm-bridge-tracks.ps1"), "-SongIds", ($ids -join ","), "-PlaylistKey", $PlaylistKey, "-ConfigPath", $ConfigPath, "-ValidateOnly", "-Json")
        Invoke-BridgeScript -Arguments $args
    }

    "playTheme" {
        if ([string]::IsNullOrWhiteSpace($Theme)) { throw "Theme is required for action 'playTheme'." }
        $ids = Get-TargetSongIds
        if ($DryRun) {
            $themePreview = Get-BridgeThemePreview -ThemeValue $Theme -DescriptionValue $Description
            $replacePreviewArgs = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "replace-ncm-bridge-tracks.ps1"), "-SongIds", ($ids -join ","), "-PlaylistKey", $PlaylistKey, "-ConfigPath", $ConfigPath, "-ValidateOnly", "-Json")
            $replacePreview = Invoke-BridgeScript -Arguments $replacePreviewArgs
            $config = Read-BridgeConfig -Path $ConfigPath
            $key = if ([string]::IsNullOrWhiteSpace($PlaylistKey)) { "$($config.activePlaylistKey)" } else { $PlaylistKey.Trim() }
            $entry = Get-BridgePlaylistEntry -Config $config -Key $key
            . (Join-Path $repoRoot "netease-music-cli\OrpheusControl.ps1")
            $playUrl = Invoke-OrpheusCommand -Name "play_playlist" -Params @{ id = "$($entry.originalId)" } -DryRun 6>$null
            [pscustomobject]@{
                success = $true
                action = "playTheme"
                code = "DRY_RUN"
                message = "Bridge theme playback previewed. No remote write or real playback was performed."
                dryRun = $true
                verified = $false
                playlistKey = $key
                theme = $themePreview
                replace = $replacePreview
                playUrl = $playUrl
            }
            break
        }

        $args = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "play-ncm-bridge-theme.ps1"), "-Theme", $Theme, "-SongIds", ($ids -join ","), "-PlaylistKey", $PlaylistKey, "-ConfigPath", $ConfigPath, "-Json")
        if (-not [string]::IsNullOrWhiteSpace($Description)) { $args += @("-Description", $Description) }
        $playThemeResult = Invoke-BridgeScript -Arguments $args
        if ($Verify) {
            $verification = Invoke-PlaybackVerification -ExpectedTitle $ExpectedTitle -ExpectedArtist $ExpectedArtist
            $playThemeResult | Add-Member -NotePropertyName verified -NotePropertyValue ([bool]$verification.success) -Force
            $playThemeResult | Add-Member -NotePropertyName verification -NotePropertyValue $verification -Force
            $playThemeResult.code = if ($verification.success) { "VERIFIED" } else { "NOT_VERIFIED" }
            $playThemeResult.message = if ($verification.success) { "Playback verified by SMTC." } else { "Playback was not verified by SMTC." }
            $playThemeResult.success = [bool]$verification.success
        }
        $playThemeResult
    }
}

Write-BridgeResult -Value $result
