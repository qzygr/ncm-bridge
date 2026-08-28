<#
主要作用：显式发起一次真实播放，并通过 Windows SMTC 验证结果。
输入：Json 开关、目标歌曲原始 ID、期望标题与期望歌手。
输出：播放验证结果；登录、协议或 SMTC 失败时标明受影响组件并以非零退出码结束。
#>

param(
    [switch]$Json,
    [string]$OriginalId = "2694779693",
    [string]$ExpectedTitle = "Eclipse",
    [string]$ExpectedArtist = "Aimer"
)

$ErrorActionPreference = "Stop"
$scriptsRoot = Split-Path -Parent $PSScriptRoot
$invokeScript = Join-Path $scriptsRoot "entry\invoke-ncm-bridge.ps1"

$raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $invokeScript `
    -Action playSong `
    -OriginalId $OriginalId `
    -ExpectedTitle $ExpectedTitle `
    -ExpectedArtist $ExpectedArtist `
    -Verify `
    -Json 2>&1

$result = $null
$parseError = $null
try { $result = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop }
catch { $parseError = $_.Exception.Message }

$passed = $LASTEXITCODE -eq 0 -and $result -and $result.code -eq "VERIFIED" -and $result.verified
$component = if ($result -and $result.code -eq "LOGIN_REQUIRED") { "login" } elseif ($parseError) { "entry" } else { "playback" }
$detail = if ($passed) { "SMTC verified originalId=$OriginalId" } elseif ($parseError) { $parseError } elseif ($result) { "$($result.code): $($result.message)" } else { ($raw | Out-String).Trim() }

$report = [pscustomobject]@{
    Success = [bool]$passed
    Layer = "playback"
    Summary = [pscustomobject]@{ Total = 1; Passed = if ($passed) { 1 } else { 0 }; Failed = if ($passed) { 0 } else { 1 } }
    AffectedComponents = if ($passed) { @() } else { @($component) }
    Results = @([pscustomobject]@{ Component = $component; Name = "playSong verified by SMTC"; Passed = [bool]$passed; Detail = $detail })
    Playback = $result
}

if ($Json) { $report | ConvertTo-Json -Depth 10 } else { $report }
if (-not $passed) { exit 1 }
