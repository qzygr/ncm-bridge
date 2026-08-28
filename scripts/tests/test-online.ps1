<#
主要作用：在已登录环境中测试搜索、状态与 SMTC 只读路径。
输入：Json、搜索条件与期望元数据。
输出：联网测试汇总及逐项结果；未登录时报告登录失败。
#>

param(
    [switch]$Json,
    [string]$SearchKeyword = "Eclipse Aimer",
    [string]$ExactTitle = "Eclipse",
    [string]$Artist = "Aimer",
    [string]$OriginalId = "2694779693",
    [string]$ExpectedTitle = "Eclipse",
    [string]$ExpectedArtist = "Aimer"
)

$ErrorActionPreference = "Stop"
$outputJson = [bool]$Json
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
    # 非交互宿主可能禁止修改编码，保持默认输出即可继续测试。
}

$LoginWindowCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\workflows\start-ncm-cli-login.ps1 -Json"

<#
主要作用：构造统一的联网测试结果项。
输入：分类、名称、通过状态和可选详情。
输出：包含 Category、Name、Passed、Detail 的测试对象。
#>
function New-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
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
主要作用：执行单个联网测试并把异常记录为失败结果。
输入：分类、名称与待执行的脚本块。
输出：成功或失败的统一测试结果对象。
#>
function Invoke-TestStep {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    try {
        $detail = & $Action
        New-TestResult -Category $Category -Name $Name -Passed $true -Detail $detail
    }
    catch {
        New-TestResult -Category $Category -Name $Name -Passed $false -Detail $_.Exception.Message
    }
}

<#
主要作用：调用统一入口并解析其 JSON 响应。
输入：传递给 powershell 的命令行参数数组。
输出：解析后的桥接结果对象；子进程失败时抛出异常。
#>
function Invoke-BridgeJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $raw = & powershell @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: powershell $($Arguments -join ' ')"
    }

    ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
}

$scriptsRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $scriptsRoot
$invokeScript = Join-Path $scriptsRoot "entry\invoke-ncm-bridge.ps1"
$results = New-Object System.Collections.Generic.List[object]
$loginReady = $false

$results.Add((Invoke-TestStep -Category "environment" -Name "ncm-cli availability" -Action {
    $command = Get-Command "ncm-cli" -ErrorAction Stop
    $version = (& ncm-cli --version).Trim()
    if (-not $version) {
        throw "ncm-cli --version returned no output."
    }
    "ncm-cli $version ($($command.Source))"
}))

$results.Add((Invoke-TestStep -Category "login" -Name "account login status" -Action {
    . (Join-Path $scriptsRoot "modules\NcmBridge.Cli.ps1")
    $parsed = Invoke-NcmCliLoginCheck
    if (-not $parsed.success) {
        $message = if ($parsed.message) { $parsed.message } else { "Not logged in." }
        throw ($message + " Use the desktop login flow instead: " + $LoginWindowCommand + ". After launching it, stop here and wait for QR login to complete before rerunning this test.")
    }

    if ($parsed.message) {
        $script:loginReady = $true
        $parsed.message
    }
    else {
        $script:loginReady = $true
        "Logged in"
    }
}))

if (-not $loginReady) {
    $summary = [pscustomobject]@{ Total = $results.Count; Passed = 0; Failed = 1 }
    $report = [pscustomobject]@{
        Success = $false
        Layer = "online"
        Summary = $summary
        AffectedComponents = @("login")
        Results = @($results)
    }
    if ($outputJson) { $report | ConvertTo-Json -Depth 8 } else { $report }
    exit 1
}

$results.Add((Invoke-TestStep -Category "live" -Name "searchSong returns compact records" -Action {
    $result = Invoke-BridgeJson -Arguments @(
        "-ExecutionPolicy", "Bypass",
        "-File", $invokeScript,
        "-Action", "searchSong",
        "-Keyword", $SearchKeyword,
        "-ExactTitle", $ExactTitle,
        "-Artist", $Artist,
        "-Limit", "1",
        "-Json"
    )

    if ($result.action -ne "searchSong") { throw "Unexpected action: $($result.action)" }
    if ($result.count -lt 1) { throw "Expected at least one record." }
    if (-not $result.records[0].originalId -or -not $result.records[0].encryptedId) { throw "Missing compact IDs." }
    "found=$($result.records[0].name)"
}))

$results.Add((Invoke-TestStep -Category "live" -Name "SMTC read path returns JSON" -Action {
    $result = Invoke-BridgeJson -Arguments @(
        "-ExecutionPolicy", "Bypass",
        "-File", $invokeScript,
        "-Action", "verifyPlayback",
        "-ExpectedTitle", $ExpectedTitle,
        "-ExpectedArtist", $ExpectedArtist,
        "-Attempts", "1",
        "-RetryDelayMs", "0",
        "-InitialDelayMs", "0",
        "-Json"
    )

    if ($result.action -ne "verifyPlayback") { throw "Unexpected action: $($result.action)" }
    if (-not $result.smtc) { throw "Missing SMTC result." }
    "code=$($result.code)"
}))

$summary = [pscustomobject]@{
    Total = $results.Count
    Passed = @($results | Where-Object { $_.Passed }).Count
    Failed = @($results | Where-Object { -not $_.Passed }).Count
}
$affectedComponents = @($results | Where-Object { -not $_.Passed } | ForEach-Object { $_.Category } | Select-Object -Unique)

$report = [pscustomobject]@{
    Success = ($summary.Failed -eq 0)
    Layer = "online"
    Summary = $summary
    AffectedComponents = $affectedComponents
    Results = @($results | ForEach-Object { $_ })
}

if ($outputJson) {
    $report | ConvertTo-Json -Depth 8
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
