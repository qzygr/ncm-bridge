param(
    [switch]$Json,
    [int]$Attempts = 5,
    [int]$RetryDelayMs = 500,
    [int]$InitialDelayMs = 300
)

$ErrorActionPreference = "Stop"

function Get-WinRtAsyncResult {
    param(
        [Parameter(Mandatory = $true)]
        [object]$AsyncOperation,

        [Parameter(Mandatory = $true)]
        [Type]$ResultType
    )

    $asTaskDefinition = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq "AsTask" -and
            $_.IsGenericMethodDefinition -and
            $_.GetParameters().Count -eq 1
        } |
        Select-Object -First 1

    if (-not $asTaskDefinition) {
        throw "System.WindowsRuntimeSystemExtensions.AsTask<T> not found."
    }

    $asTask = $asTaskDefinition.MakeGenericMethod($ResultType)
    $task = $asTask.Invoke($null, @($AsyncOperation))
    return $task.GetAwaiter().GetResult()
}

function Get-NeteaseSmtcStatus {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]

    $manager = Get-WinRtAsyncResult `
        -AsyncOperation ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) `
        -ResultType ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])

    $session = $manager.GetSessions() |
        Where-Object { $_.SourceAppUserModelId -eq "cloudmusic.exe" } |
        Select-Object -First 1

    if (-not $session) {
        return [pscustomobject]@{
            Success = $false
            Error = "NETEASE_SESSION_NOT_FOUND"
            Detail = "No Netease Cloud Music SMTC session was found. Make sure the client is running and SMTC is enabled in Settings > System > SMTC."
            Source = "smtc"
            App = $null
            Title = $null
            Artist = $null
            PlaybackStatus = $null
            PositionSeconds = $null
            StartSeconds = $null
            EndSeconds = $null
            TimelineAvailable = $false
            Attempt = 1
            Attempts = 1
            RetryDelayMs = 0
        }
    }

    $media = Get-WinRtAsyncResult `
        -AsyncOperation ($session.TryGetMediaPropertiesAsync()) `
        -ResultType ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])

    $timeline = $session.GetTimelineProperties()
    $playback = $session.GetPlaybackInfo()

    $positionSeconds = [int][Math]::Round($timeline.Position.TotalSeconds)
    $startSeconds = [int][Math]::Round($timeline.StartTime.TotalSeconds)
    $endSeconds = [int][Math]::Round($timeline.EndTime.TotalSeconds)
    $timelineAvailable = $endSeconds -gt $startSeconds
    $detail = if ($timelineAvailable) { $null } else { "Official SMTC does not support timeline." }

    return [pscustomobject]@{
        Success = $true
        Error = $null
        Detail = $detail
        Source = "smtc"
        App = $session.SourceAppUserModelId
        Title = $media.Title
        Artist = $media.Artist
        PlaybackStatus = $playback.PlaybackStatus.ToString()
        PositionSeconds = $positionSeconds
        StartSeconds = $startSeconds
        EndSeconds = $endSeconds
        TimelineAvailable = $timelineAvailable
        Attempt = 1
        Attempts = 1
        RetryDelayMs = 0
    }
}

function Invoke-NeteaseSmtcRead {
    param(
        [int]$Attempts = 5,
        [int]$RetryDelayMs = 500,
        [int]$InitialDelayMs = 300
    )

    if ($Attempts -lt 1) { $Attempts = 1 }
    if ($RetryDelayMs -lt 0) { $RetryDelayMs = 0 }
    if ($InitialDelayMs -lt 0) { $InitialDelayMs = 0 }

    if ($InitialDelayMs -gt 0) {
        Start-Sleep -Milliseconds $InitialDelayMs
    }

    $lastResult = $null
    $lastError = $null

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $result = Get-NeteaseSmtcStatus
            $result | Add-Member -NotePropertyName Attempt -NotePropertyValue $attempt -Force
            $result | Add-Member -NotePropertyName Attempts -NotePropertyValue $Attempts -Force
            $result | Add-Member -NotePropertyName RetryDelayMs -NotePropertyValue $RetryDelayMs -Force

            if ($result.Success -and -not [string]::IsNullOrWhiteSpace($result.Title)) {
                return $result
            }

            $lastResult = $result
        }
        catch {
            $lastError = $_.Exception.Message
            $lastResult = [pscustomobject]@{
                Success = $false
                Error = "SMTC_READ_FAILED"
                Detail = $lastError
                Source = "smtc"
                App = $null
                Title = $null
                Artist = $null
                PlaybackStatus = $null
                PositionSeconds = $null
                StartSeconds = $null
                EndSeconds = $null
                TimelineAvailable = $false
                Attempt = $attempt
                Attempts = $Attempts
                RetryDelayMs = $RetryDelayMs
            }
        }

        if ($attempt -lt $Attempts -and $RetryDelayMs -gt 0) {
            Start-Sleep -Milliseconds $RetryDelayMs
        }
    }

    if ($lastResult) {
        return $lastResult
    }

    try {
        return Get-NeteaseSmtcStatus
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Error = "SMTC_READ_FAILED"
            Detail = $_.Exception.Message
            Source = "smtc"
            App = $null
            Title = $null
            Artist = $null
            PlaybackStatus = $null
            PositionSeconds = $null
            StartSeconds = $null
            EndSeconds = $null
            TimelineAvailable = $false
            Attempt = $Attempts
            Attempts = $Attempts
            RetryDelayMs = $RetryDelayMs
        }
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    $result = Invoke-NeteaseSmtcRead -Attempts $Attempts -RetryDelayMs $RetryDelayMs -InitialDelayMs $InitialDelayMs

    if ($Json) {
        $result | ConvertTo-Json -Compress
    }
    elseif ($result.Success) {
        "Title: $($result.Title)"
        "Artist: $($result.Artist)"
        "PlaybackStatus: $($result.PlaybackStatus)"
        "Timeline: $($result.PositionSeconds)|$($result.EndSeconds)"
        "TimelineAvailable: $($result.TimelineAvailable)"
        "Attempt: $($result.Attempt)/$($result.Attempts)"
        if ($result.Detail) {
            "Detail: $($result.Detail)"
        }
    }
    else {
        "None"
    }
}
