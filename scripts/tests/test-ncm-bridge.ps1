<#
主要作用：聚合前置、在线、播放和歌单写入测试，是仓库推荐的总自检入口。
输入：Json 与按副作用分层的开关；默认只运行前置完整性测试。
输出：分层测试汇总及逐项结果；失败时以非零退出码结束。
#>

param(
    [switch]$Json,
    [switch]$Online,
    [switch]$Playback,
    [switch]$PlaylistWrite,
    [switch]$ApplyPlaylistWrite,
    [string]$PlaylistSongIds = "",
    [switch]$Live,
    [switch]$IncludePlayback
)

$ErrorActionPreference = "Stop"
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
    # 非交互宿主可能禁止修改编码，保持默认输出即可继续测试。
}
if ($Live) { $Online = $true }
if ($IncludePlayback) { $Playback = $true }

<#
主要作用：构造统一的聚合测试结果项。
输入：分类、名称、通过状态和可选详情。
输出：包含 Category、Name、Passed、Detail 的测试对象。
#>
function New-TestResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [bool]$Passed,

        [string]$Detail = $null
    )

    [pscustomobject]@{
        Category = $Category
        Name = $Name
        Passed = $Passed
        Detail = $Detail
    }
}

<#
主要作用：执行单个聚合测试步骤并捕获异常。
输入：分类、名称与待执行的脚本块。
输出：成功或失败的统一测试结果对象。
#>
function Invoke-TestStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    try {
        $detail = & $Action
        return New-TestResult -Category $Category -Name $Name -Passed $true -Detail $detail
    }
    catch {
        return New-TestResult -Category $Category -Name $Name -Passed $false -Detail $_.Exception.Message
    }
}

<#
主要作用：使用 PowerShell 解析器验证指定脚本语法。
输入：PowerShell 脚本路径。
输出：成功时返回 Syntax OK 文本；失败时抛出异常。
#>
function Test-PowerShellSyntax {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "Syntax error: $($errors[0].Message)"
    }

    return "Syntax OK"
}

<#
主要作用：判断当前操作系统是否为 Windows。
输入：无。
输出：布尔值，true 表示 Windows 环境。
#>
function Test-IsWindowsEnvironment {
    if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
        return [bool]$IsWindows
    }

    return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

$scriptsRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $scriptsRoot
$preflightScript = Join-Path $PSScriptRoot "test-preflight.ps1"
$onlineScript = Join-Path $PSScriptRoot "test-online.ps1"
$playbackScript = Join-Path $PSScriptRoot "test-playback.ps1"
$playlistWriteScript = Join-Path $PSScriptRoot "test-playlist-write.ps1"

$results = New-Object System.Collections.Generic.List[object]

$results.Add((Invoke-TestStep -Category "preflight" -Name "environment and Orpheus integrity" -Action {
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $preflightScript, "-Json")
    $raw = & powershell @arguments
    $report = $null
    try { $report = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "test-preflight.ps1 returned invalid JSON: $($raw -join ' ')" }
    if ($LASTEXITCODE -ne 0) {
        $affected = @($report.AffectedComponents) -join ", "
        throw "test-preflight.ps1 failed. Affected components: $affected"
    }

    if (-not $report.Success -and -not $report.success) {
        $affected = @($report.AffectedComponents) -join ", "
        throw "test-preflight.ps1 reported failure. Affected components: $affected"
    }

    "$($report.Summary.Passed)/$($report.Summary.Total) passed"
}))

$results.Add((Invoke-TestStep -Category "environment" -Name "Node.js availability" -Action {
    $nodeVersionText = (& node --version).Trim()
    if (-not $nodeVersionText) {
        throw "node --version returned no output."
    }

    $versionString = $nodeVersionText.TrimStart("v")
    $version = [Version]$versionString
    if ($version.Major -lt 18) {
        throw "Node.js version is too old: $nodeVersionText"
    }

    "Node.js $nodeVersionText"
}))

if ($Online) {
    $results.Add((Invoke-TestStep -Category "online" -Name "login and read-only online operations" -Action {
        $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $onlineScript, "-Json")
        $raw = & powershell @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "test-online.ps1 failed."
        }

        $report = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
        if (-not $report.Success -and -not $report.success) {
            throw "test-online.ps1 reported failure."
        }

        "$($report.Summary.Passed)/$($report.Summary.Total) passed"
    }))
}
else {
    $results.Add((New-TestResult -Category "online" -Name "login and read-only online operations" -Passed $true -Detail "Skipped. Re-run with -Online for login, search, status, and SMTC checks."))
}

if ($Playback) {
    $results.Add((Invoke-TestStep -Category "playback" -Name "real playback verified by SMTC" -Action {
        $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $playbackScript -Json
        if ($LASTEXITCODE -ne 0) { throw "test-playback.ps1 failed: $($raw -join ' ')" }
        $report = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
        if (-not $report.Success) { throw "test-playback.ps1 reported failure." }
        "$($report.Summary.Passed)/$($report.Summary.Total) passed"
    }))
}

if ($PlaylistWrite) {
    $results.Add((Invoke-TestStep -Category "playlist-write" -Name "playlist replacement validation" -Action {
        if ([string]::IsNullOrWhiteSpace($PlaylistSongIds)) { throw "-PlaylistSongIds is required with -PlaylistWrite." }
        $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $playlistWriteScript, "-SongIds", $PlaylistSongIds, "-Json")
        if ($ApplyPlaylistWrite) { $arguments += "-Apply" }
        $raw = & powershell @arguments
        if ($LASTEXITCODE -ne 0) { throw "test-playlist-write.ps1 failed: $($raw -join ' ')" }
        $report = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
        if (-not $report.Success) { throw "test-playlist-write.ps1 reported failure." }
        "$($report.Summary.Passed)/$($report.Summary.Total) passed"
    }))
}

$summary = [pscustomobject]@{
    Total = $results.Count
    Passed = @($results | Where-Object { $_.Passed }).Count
    Failed = @($results | Where-Object { -not $_.Passed }).Count
}
$affectedComponents = @($results | Where-Object { -not $_.Passed } | ForEach-Object { $_.Category } | Select-Object -Unique)

$report = [pscustomobject]@{
    Success = ($summary.Failed -eq 0)
    Layer = "layered"
    IncludesPlayback = [bool]$Playback
    Summary = $summary
    AffectedComponents = $affectedComponents
    Results = @($results | ForEach-Object { $_ })
}

if ($Json) {
    $report | ConvertTo-Json -Depth 6
    exit
}

foreach ($item in $results) {
    $status = if ($item.Passed) { "[PASS]" } else { "[FAIL]" }
    $detail = if ($item.Detail) { " - $($item.Detail)" } else { "" }
    Write-Host "$status [$($item.Category)] $($item.Name)$detail"
}

Write-Host ""
Write-Host "Summary: $($summary.Passed)/$($summary.Total) passed, $($summary.Failed) failed."

if ($summary.Failed -gt 0) {
    exit 1
}
