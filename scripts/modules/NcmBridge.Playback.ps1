<#
主要作用：通过 Windows SMTC 验证目标歌曲是否真正进入播放状态。
输入：期望标题、歌手、重试次数与重试延迟。
输出：匹配结果、诊断信息，以及 VERIFIED 或 NOT_VERIFIED 语义所需字段。
#>

$ErrorActionPreference = "Stop"

<#
主要作用：按不区分大小写的包含关系比较媒体文本。
输入：实际文本与期望文本。
输出：期望为空或实际文本包含期望文本时返回 true。
#>
function Test-TextMatch {
    param(
        [string]$Actual,
        [string]$Expected
    )

    if ([string]::IsNullOrWhiteSpace($Expected)) { return $true }
    if ([string]::IsNullOrWhiteSpace($Actual)) { return $false }
    return $Actual.IndexOf($Expected, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

<#
主要作用：构造一次播放验证失败时的详细诊断对象。
输入：期望信息、最后一次 SMTC 状态和重试配置。
输出：可写入 JSON 结果的诊断对象。
#>
function New-PlaybackVerificationDiagnostics {
    param(
        [object]$Status,
        [string]$ExpectedTitle = "",
        [string]$ExpectedArtist = "",
        [bool]$TitleMatched,
        [bool]$ArtistMatched,
        [bool]$PlayingMatched,
        [int]$Attempts,
        [int]$RetryDelayMs,
        [int]$InitialDelayMs,
        [string]$UrlLaunched = ""
    )

    $actualTitle = if ($Status) { "$($Status.Title)" } else { $null }
    $actualArtist = if ($Status) { "$($Status.Artist)" } else { $null }
    $actualStatus = if ($Status) { "$($Status.PlaybackStatus)" } else { $null }
    $smtcSuccess = if ($Status) { [bool]$Status.Success } else { $false }
    $mismatchReasons = New-Object System.Collections.Generic.List[string]

    if (-not $Status) {
        $mismatchReasons.Add("smtc_status_missing")
    }
    elseif (-not $smtcSuccess) {
        $mismatchReasons.Add("smtc_read_failed")
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedTitle) -and -not $TitleMatched) {
        if ([string]::IsNullOrWhiteSpace($actualTitle)) {
            $mismatchReasons.Add("title_missing")
        }
        else {
            $mismatchReasons.Add("title_mismatch")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedArtist) -and -not $ArtistMatched) {
        if ([string]::IsNullOrWhiteSpace($actualArtist)) {
            $mismatchReasons.Add("artist_missing")
        }
        else {
            $mismatchReasons.Add("artist_mismatch")
        }
    }

    if (-not $PlayingMatched) {
        if ([string]::IsNullOrWhiteSpace($actualStatus)) {
            $mismatchReasons.Add("playback_status_missing")
        }
        else {
            $mismatchReasons.Add("playback_status_not_playing")
        }
    }

    [pscustomobject]@{
        expected = [pscustomobject]@{
            title = $ExpectedTitle
            artist = $ExpectedArtist
            status = "Playing"
        }
        actual = [pscustomobject]@{
            title = $actualTitle
            artist = $actualArtist
            status = $actualStatus
        }
        matches = [pscustomobject]@{
            title = $TitleMatched
            artist = $ArtistMatched
            status = $PlayingMatched
        }
        mismatchReasons = @($mismatchReasons)
        urlLaunched = if ([string]::IsNullOrWhiteSpace($UrlLaunched)) { $null } else { $UrlLaunched }
        smtcSuccess = $smtcSuccess
        smtcError = if ($Status) { $Status.Error } else { $null }
        smtcDetail = if ($Status) { $Status.Detail } else { $null }
        attempt = if ($Status) { $Status.VerifyAttempt } else { $null }
        attempts = $Attempts
        retryDelayMs = $RetryDelayMs
        initialDelayMs = $InitialDelayMs
    }
}

<#
主要作用：轮询 SMTC，确认标题、歌手和 Playing 状态同时匹配。
输入：期望标题、期望歌手、尝试次数、初始等待与重试延迟。
输出：包含 verified、状态快照和诊断信息的验证结果对象。
#>
function Invoke-PlaybackVerification {
    param(
        [string]$ExpectedTitle = "",
        [string]$ExpectedArtist = "",
        [string]$UrlLaunched = "",
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [int]$Attempts = 8,
        [int]$RetryDelayMs = 700,
        [int]$InitialDelayMs = 500
    )

    . (Join-Path $RepoRoot "scripts\OrpheusControl.ps1")
    if ($Attempts -lt 1) { $Attempts = 1 }
    if ($RetryDelayMs -lt 0) { $RetryDelayMs = 0 }
    if ($InitialDelayMs -lt 0) { $InitialDelayMs = 0 }

    if ($InitialDelayMs -gt 0) {
        Start-Sleep -Milliseconds $InitialDelayMs
    }

    $status = $null
    $titleMatched = $false
    $artistMatched = $false
    $playingMatched = $false
    $verified = $false
    $matchedAttempt = $null

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $status = Get-NeteasePlaybackStatus -Attempts 1 -RetryDelayMs 0 -InitialDelayMs 0
        $titleMatched = Test-TextMatch -Actual "$($status.Title)" -Expected $ExpectedTitle
        $artistMatched = Test-TextMatch -Actual "$($status.Artist)" -Expected $ExpectedArtist
        $playingMatched = "$($status.PlaybackStatus)" -eq "Playing"
        $verified = [bool]($status.Success -and $titleMatched -and $artistMatched -and $playingMatched)

        if ($status) {
            $status | Add-Member -NotePropertyName VerifyAttempt -NotePropertyValue $attempt -Force
            $status | Add-Member -NotePropertyName VerifyAttempts -NotePropertyValue $Attempts -Force
        }

        if ($verified) {
            $matchedAttempt = $attempt
            break
        }

        if ($attempt -lt $Attempts -and $RetryDelayMs -gt 0) {
            Start-Sleep -Milliseconds $RetryDelayMs
        }
    }

    $result = [pscustomobject]@{
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
        attempts = $Attempts
        retryDelayMs = $RetryDelayMs
        initialDelayMs = $InitialDelayMs
        smtc = $status
    }

    if (-not $verified) {
        $result | Add-Member -NotePropertyName diagnostics -NotePropertyValue (New-PlaybackVerificationDiagnostics `
            -Status $status `
            -ExpectedTitle $ExpectedTitle `
            -ExpectedArtist $ExpectedArtist `
            -TitleMatched $titleMatched `
            -ArtistMatched $artistMatched `
            -PlayingMatched $playingMatched `
            -Attempts $Attempts `
            -RetryDelayMs $RetryDelayMs `
            -InitialDelayMs $InitialDelayMs `
            -UrlLaunched $UrlLaunched) -Force
    }

    $result
}
