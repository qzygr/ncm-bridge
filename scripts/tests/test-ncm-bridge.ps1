<#
主要作用：聚合快速和可选联网测试，是仓库推荐的总自检入口。
输入：Json、Live 与 IncludePlayback 开关。
输出：分层测试汇总及逐项结果；失败时以非零退出码结束。
#>

param(
    [switch]$Json,
    [switch]$Live,
    [switch]$IncludePlayback
)

$ErrorActionPreference = "Stop"

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
$fastScript = Join-Path $PSScriptRoot "test-invoke-fast.ps1"
$liveScript = Join-Path $PSScriptRoot "test-invoke-live.ps1"

$results = New-Object System.Collections.Generic.List[object]

$results.Add((Invoke-TestStep -Category "fast" -Name "offline invoke layer" -Action {
    $arguments = @("-ExecutionPolicy", "Bypass", "-File", $fastScript, "-Json")
    $raw = & powershell @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "test-invoke-fast.ps1 failed."
    }

    $report = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
    if (-not $report.Success -and -not $report.success) {
        throw "test-invoke-fast.ps1 reported failure."
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

if ($Live) {
    $results.Add((Invoke-TestStep -Category "live" -Name "online invoke layer" -Action {
        $arguments = @("-ExecutionPolicy", "Bypass", "-File", $liveScript, "-Json")
        if ($IncludePlayback) { $arguments += "-IncludePlayback" }
        $raw = & powershell @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "test-invoke-live.ps1 failed."
        }

        $report = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
        if (-not $report.Success -and -not $report.success) {
            throw "test-invoke-live.ps1 reported failure."
        }

        "$($report.Summary.Passed)/$($report.Summary.Total) passed"
    }))
}
else {
    $results.Add((New-TestResult -Category "live" -Name "online invoke layer" -Passed $true -Detail "Skipped. Re-run with -Live for search/SMTC checks, add -IncludePlayback for real playback."))
}

$summary = [pscustomobject]@{
    Total = $results.Count
    Passed = @($results | Where-Object { $_.Passed }).Count
    Failed = @($results | Where-Object { -not $_.Passed }).Count
}

$report = [pscustomobject]@{
    Success = ($summary.Failed -eq 0)
    Layer = if ($Live) { "fast+live" } else { "fast" }
    IncludesPlayback = [bool]$IncludePlayback
    Summary = $summary
    Results = $results
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
