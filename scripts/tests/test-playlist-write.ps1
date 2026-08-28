<#
主要作用：验证歌单替换的预演路径，并在显式授权时执行真实远端写入。
输入：加密歌曲 ID、歌单 key、可选配置路径、Apply 与 Json 开关。
输出：验证、dry-run 和可选写入结果；失败时标明 login、playlist 或 remote-write 组件。
#>

param(
    [Parameter(Mandatory = $true)][string]$SongIds,
    [string]$PlaylistKey = "",
    [string]$ConfigPath = "",
    [switch]$Apply,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptsRoot = Split-Path -Parent $PSScriptRoot
$invokeScript = Join-Path $scriptsRoot "entry\invoke-ncm-bridge.ps1"

function Invoke-PlaylistWriteAction {
    <#
    主要作用：调用统一入口的歌单替换动作并解析 JSON 结果。
    输入：动作名、是否 dry-run、是否真实写入以及调用参数。
    输出：统一入口返回的 JSON 对象；无法解析时抛出异常。
    #>
    param([Parameter(Mandatory = $true)][string]$Action, [switch]$DryRun)

    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $invokeScript, "-Action", $Action, "-SongIds", $SongIds, "-Json")
    if ($DryRun) { $arguments += "-DryRun" }
    if ($PlaylistKey) { $arguments += @("-PlaylistKey", $PlaylistKey) }
    if ($ConfigPath) { $arguments += @("-ConfigPath", $ConfigPath) }
    $raw = & powershell @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($raw | Out-String).Trim() }
    ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
}

$results = New-Object System.Collections.Generic.List[object]
try {
    $validation = Invoke-PlaylistWriteAction -Action "validateReplaceTracks"
    $results.Add([pscustomobject]@{ Component = "playlist"; Name = "track replacement validation"; Passed = $true; Detail = "$($validation.code)" })

    $preview = Invoke-PlaylistWriteAction -Action "replaceTracks" -DryRun
    $results.Add([pscustomobject]@{ Component = "remote-write"; Name = "track replacement dry-run"; Passed = $true; Detail = "$($preview.code)" })

    if ($Apply) {
        $written = Invoke-PlaylistWriteAction -Action "replaceTracks"
        $results.Add([pscustomobject]@{ Component = "remote-write"; Name = "track replacement apply"; Passed = [bool]$written.success; Detail = "$($written.code)" })
    }
}
catch {
    $message = $_.Exception.Message
    $component = if ($message -match "LOGIN_REQUIRED|login") { "login" } else { "playlist" }
    $results.Add([pscustomobject]@{ Component = $component; Name = "playlist write preflight"; Passed = $false; Detail = $message })
}

$failed = @($results | Where-Object { -not $_.Passed })
$failedCount = [int]$failed.Count
$affectedComponents = @(
    foreach ($item in $failed) {
        if ($item.Component) { [string]$item.Component }
    }
) | Select-Object -Unique
$report = [pscustomobject]@{
    Success = ($failedCount -eq 0)
    Layer = "playlist-write"
    Applied = [bool]$Apply
    Summary = [pscustomobject]@{ Total = [int]$results.Count; Passed = [int]$results.Count - $failedCount; Failed = $failedCount }
    AffectedComponents = @($affectedComponents)
    Results = @($results | ForEach-Object { $_ })
}

if ($Json) { $report | ConvertTo-Json -Depth 10 } else { $report }
if ($failedCount -gt 0) { exit 1 }
