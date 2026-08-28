<#
主要作用：作为 Agent 的统一入口，分发诊断、歌单、搜索、播放和验证动作。
输入：Action、歌曲或歌单参数、验证参数、配置路径与输出格式开关。
输出：人类可读文本或稳定的 JSON 结果对象。
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("help", "diagnose", "status", "repair", "pruneMissing", "dryRun", "searchSong", "playSong", "verifyPlayback", "playDefault", "setTheme", "replaceTracks", "validateReplaceTracks", "playTheme")]
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

<#
主要作用：按当前输出选项写入统一入口结果并结束脚本。
输入：任意已规范化的动作结果对象。
输出：JSON、压缩 JSON 或控制台文本；函数调用后退出当前脚本。
#>
function Write-BridgeResult {
    param([Parameter(Mandatory = $true)][object]$Value)

    if ($outputJson) {
        $Value | ConvertTo-Json -Depth 10 -Compress:$CompressJson
        exit
    }

    if ($Value.action -eq "help") {
        ConvertTo-BridgeHelpText -Value $Value
        return
    }

    if ($Value.message) { $Value.message }
    else { $Value | ConvertTo-Json -Depth 6 }
}

<#
主要作用：调用子工作流脚本并将其 JSON 输出解析为对象。
输入：脚本路径与传递给该脚本的参数数组。
输出：子脚本返回的解析后 JSON 对象；子脚本失败时抛出异常。
#>
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

<#
主要作用：规范化逗号分隔或数组形式的加密歌曲 ID。
输入：原始 SongIds 字符串数组。
输出：去空白、去重后的歌曲 ID 数组。
#>
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

<#
主要作用：生成主题歌单动作在 DryRun 模式下的预览结果。
输入：主题、描述、歌曲 ID、PlaylistKey 和配置路径。
输出：不执行远端写入或播放的预览对象。
#>
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

$requiresLogin = Test-NcmBridgeActionRequiresLogin -Action $Action -DryRun:([bool]$DryRun) -Verify:([bool]$Verify)
if ($requiresLogin) {
    try {
        $loginStatus = Invoke-NcmCliLoginCheck
    }
    catch {
        $loginStatus = [pscustomobject]@{
            success = $false
            message = $_.Exception.Message
        }
    }
    if (-not $loginStatus.success) {
        Write-BridgeResult -Value (New-NcmCliLoginRequiredResult -LoginStatus $loginStatus -ActionName $Action)
    }
}

$result = switch ($Action) {
    "help" {
        . (Join-Path $PSScriptRoot "NcmBridge.Help.ps1")
        New-BridgeHelpResult
    }

    "diagnose" {
        . (Join-Path $PSScriptRoot "NcmBridge.Diagnostics.ps1")
        Get-NcmBridgeDiagnostics `
            -ConfigPath $ConfigPath `
            -IncludeSmtc:([bool]$Verify) `
            -SmtcAttempts $verifyAttempts `
            -SmtcRetryDelayMs $verifyRetryDelayMs `
            -SmtcInitialDelayMs $verifyInitialDelayMs `
            -RepoRoot $repoRoot
    }

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
        . (Join-Path $PSScriptRoot "NcmBridge.Playback.ps1")
        Invoke-PlaybackVerification `
            -ExpectedTitle $ExpectedTitle `
            -ExpectedArtist $ExpectedArtist `
            -RepoRoot $repoRoot `
            -Attempts $verifyAttempts `
            -RetryDelayMs $verifyRetryDelayMs `
            -InitialDelayMs $verifyInitialDelayMs
    }

    "playSong" {
        if ([string]::IsNullOrWhiteSpace($OriginalId)) { throw "OriginalId is required for action 'playSong'." }

        . (Join-Path $repoRoot "netease-music-cli\OrpheusControl.ps1")
        $url = Invoke-OrpheusCommand -Name "play_song" -Params @{ id = "$OriginalId" } -DryRun:$DryRun 6>$null
        $verification = if ($Verify -and -not $DryRun) {
            . (Join-Path $PSScriptRoot "NcmBridge.Playback.ps1")
            Invoke-PlaybackVerification `
                -ExpectedTitle $ExpectedTitle `
                -ExpectedArtist $ExpectedArtist `
                -UrlLaunched $url `
                -RepoRoot $repoRoot `
                -Attempts $verifyAttempts `
                -RetryDelayMs $verifyRetryDelayMs `
                -InitialDelayMs $verifyInitialDelayMs
        }
        else {
            $null
        }

        [pscustomobject]@{
            success = if ($verification) { [bool]$verification.success } else { $true }
            action = "playSong"
            code = if ($DryRun) { "URL_PREVIEWED" } elseif ($verification -and $verification.success) { "VERIFIED" } elseif ($verification) { "NOT_VERIFIED" } else { "URL_LAUNCHED" }
            message = if ($verification -and $verification.success) { "Playback verified by SMTC." } elseif ($verification) { "Playback was not verified by SMTC." } elseif ($DryRun) { "Protocol URL previewed. Dry-run does not verify playback." } else { "Protocol URL launched. Use SMTC to verify playback." }
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
            . (Join-Path $PSScriptRoot "NcmBridge.Playback.ps1")
            $verification = Invoke-PlaybackVerification `
                -ExpectedTitle $ExpectedTitle `
                -ExpectedArtist $ExpectedArtist `
                -UrlLaunched "$($playThemeResult.playUrl)" `
                -RepoRoot $repoRoot `
                -Attempts $verifyAttempts `
                -RetryDelayMs $verifyRetryDelayMs `
                -InitialDelayMs $verifyInitialDelayMs
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
