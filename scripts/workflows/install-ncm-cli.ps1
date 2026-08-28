<#
主要作用：固化 ncm-cli 的非授权安装与基础环境配置流程。
输入：可选的升级、跳过安装、dry-run、fast 自检与 JSON 输出开关。
输出：包含 Node.js、npm、ncm-cli、播放器配置、登录状态和可选自检结果的对象或 JSON。

说明：本脚本不接收、不写入也不输出 appId、privateKey；账号登录必须由用户单独完成。
#>

[CmdletBinding()]
param(
    [switch]$Upgrade,
    [switch]$SkipInstall,
    [switch]$DryRun,
    [switch]$RunFastCheck,
    [switch]$Json,
    [switch]$CompressJson
)

$ErrorActionPreference = "Stop"

<#
主要作用：调用外部命令并在失败时抛出带上下文的异常。
输入：命令名称、参数数组与供错误说明使用的动作名称。
输出：外部命令的标准输出文本数组；失败时不返回。
#>
function Invoke-NcmSetupCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][string]$Action
    )

    $output = & $Command @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = ($output | Out-String).Trim()
        throw "$Action failed with exit code $LASTEXITCODE. $detail"
    }

    @($output | ForEach-Object { "$_" })
}

<#
主要作用：读取 Node.js 版本，并确保主版本满足 ncm-cli 的最低要求。
输入：无；依赖 PATH 中的 node 命令。
输出：Node.js 的规范化版本字符串；版本不足或命令缺失时抛出异常。
#>
function Get-RequiredNodeVersion {
    $nodeCommand = Get-Command "node" -ErrorAction Stop
    $versionText = (Invoke-NcmSetupCommand -Command $nodeCommand.Source -Arguments @("--version") -Action "node --version" | Select-Object -Last 1).Trim()
    $match = [regex]::Match($versionText, "v?(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)")
    if (-not $match.Success) {
        throw "Unable to parse Node.js version: $versionText"
    }

    if ([int]$match.Groups["major"].Value -lt 18) {
        throw "Node.js >= 18 is required. Current version: $versionText"
    }

    $versionText
}

<#
主要作用：从 ncm-cli 的混合控制台输出中提取 JSON，兼容升级提示前缀。
输入：ncm-cli 的原始输出文本数组与调用上下文。
输出：解析后的 JSON 对象；未找到或无法解析 JSON 时抛出异常。
#>
function ConvertFrom-NcmSetupJsonOutput {
    param(
        [Parameter(Mandatory = $true)][object[]]$Output,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $rawText = (@($Output | ForEach-Object { "$_" }) -join "`n").Trim()
    if (-not $rawText) {
        throw "$Context returned no output."
    }

    try {
        return $rawText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $jsonStart = $rawText.IndexOf("{")
        if ($jsonStart -lt 0) {
            throw "$Context output does not contain JSON: $rawText"
        }

        try {
            return $rawText.Substring($jsonStart) | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "$Context JSON parsing failed: $rawText"
        }
    }
}

<#
主要作用：读取已安装 ncm-cli 的版本信息。
输入：无；依赖 PATH 中的 ncm-cli 命令。
输出：ncm-cli 版本字符串；命令不存在时返回 null。
#>
function Get-InstalledNcmCliVersion {
    $command = Get-Command "ncm-cli" -ErrorAction SilentlyContinue
    if (-not $command) {
        return $null
    }

    $output = Invoke-NcmSetupCommand -Command $command.Source -Arguments @("--version") -Action "ncm-cli --version"
    $versionLine = @($output | Where-Object { $_ -match "^\s*\d+\.\d+\.\d+" } | Select-Object -Last 1)
    if ($versionLine.Count -gt 0) {
        return $versionLine[0].Trim()
    }

    ($output | Select-Object -Last 1).Trim()
}

<#
主要作用：安装或升级 @music163/ncm-cli。
输入：是否为 dry-run。
输出：实际执行的 npm 参数数组；dry-run 时仅返回计划参数。
#>
function Install-NcmCliPackage {
    param([bool]$IsDryRun)

    $npmCommand = Get-Command "npm" -ErrorAction Stop
    $arguments = @("install", "--global", "@music163/ncm-cli")
    if (-not $IsDryRun) {
        $null = Invoke-NcmSetupCommand -Command $npmCommand.Source -Arguments $arguments -Action "npm install -g @music163/ncm-cli"
    }

    @($arguments)
}

<#
主要作用：设置 ncm-cli 的默认播放器占位配置。
输入：是否为 dry-run。
输出：配置完成时返回 player 值 mpv；dry-run 时返回 planned 值。
#>
function Set-NcmCliDefaultPlayer {
    param([bool]$IsDryRun)

    if ($IsDryRun) {
        return "mpv"
    }

    $command = Get-Command "ncm-cli" -ErrorAction Stop
    $null = Invoke-NcmSetupCommand -Command $command.Source -Arguments @("config", "set", "player", "mpv") -Action "ncm-cli config set player mpv"
    "mpv"
}

<#
主要作用：只读检查 ncm-cli 的账号登录状态，不触发登录或任何远端写入。
输入：无；依赖 PATH 中的 ncm-cli 命令。
输出：包含 checked、success、message 与 error 字段的登录状态对象。
#>
function Get-NcmCliLoginStatus {
    $command = Get-Command "ncm-cli" -ErrorAction Stop
    try {
        $output = Invoke-NcmSetupCommand -Command $command.Source -Arguments @("login", "--check") -Action "ncm-cli login --check"
        $parsed = ConvertFrom-NcmSetupJsonOutput -Output $output -Context "ncm-cli login --check"
        [pscustomobject]@{
            checked = $true
            success = [bool]$parsed.success
            message = if ($parsed.message) { "$($parsed.message)" } else { $null }
            error = $null
        }
    }
    catch {
        [pscustomobject]@{
            checked = $true
            success = $false
            message = $null
            error = $_.Exception.Message
        }
    }
}

<#
主要作用：运行项目的离线 fast 自检，不执行联网、远端写入、真实播放或 SMTC 读取。
输入：仓库根目录与是否为 dry-run。
输出：fast 自检解析后的报告对象；dry-run 时返回 null。
#>
function Invoke-NcmSetupFastCheck {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [bool]$IsDryRun
    )

    if ($IsDryRun) {
        return $null
    }

    $scriptPath = Join-Path $RepoRoot "scripts\tests\test-invoke-fast.ps1"
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Fast self-check failed: $(($output | Out-String).Trim())"
    }

    ($output -join "`n") | ConvertFrom-Json -ErrorAction Stop
}

<#
主要作用：将安装流程结果按普通对象或 JSON 形式输出。
输入：结果对象、JSON 开关与压缩 JSON 开关。
输出：控制台结果；Json 为 false 时输出 PowerShell 对象。
#>
function Write-NcmSetupResult {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [bool]$AsJson,
        [bool]$ShouldCompressJson
    )

    if ($AsJson) {
        $Value | ConvertTo-Json -Depth 8 -Compress:$ShouldCompressJson
    }
    else {
        $Value
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nodeVersion = Get-RequiredNodeVersion
$installedVersion = Get-InstalledNcmCliVersion
$installArguments = $null

if ($Upgrade -or -not $installedVersion) {
    if ($SkipInstall) {
        if (-not $installedVersion) {
            throw "ncm-cli is not installed and -SkipInstall was specified."
        }
    }
    else {
        $installArguments = Install-NcmCliPackage -IsDryRun ([bool]$DryRun)
        if (-not $DryRun) {
            $installedVersion = Get-InstalledNcmCliVersion
        }
    }
}

$player = if ($installedVersion -or $DryRun) { Set-NcmCliDefaultPlayer -IsDryRun ([bool]$DryRun) } else { $null }
$fastCheck = if ($RunFastCheck) { Invoke-NcmSetupFastCheck -RepoRoot $repoRoot -IsDryRun ([bool]$DryRun) } else { $null }
$login = if ($DryRun) {
    [pscustomobject]@{ checked = $false; success = $false; message = "Dry-run does not check login."; error = $null }
}
else {
    Get-NcmCliLoginStatus
}

$result = [pscustomobject]@{
    success = $true
    action = "installNcmCli"
    code = if ($DryRun) { "DRY_RUN" } elseif ($login.success) { "OK" } else { "LOGIN_REQUIRED" }
    message = if ($DryRun) {
        "ncm-cli installation and configuration plan generated."
    }
    elseif ($login.success) {
        "ncm-cli installation and configuration completed."
    }
    else {
        "ncm-cli installation and configuration completed. Complete login separately before network actions."
    }
    dryRun = [bool]$DryRun
    node = [pscustomobject]@{ version = $nodeVersion }
    ncmCli = [pscustomobject]@{
        version = $installedVersion
        installedOrUpgraded = [bool]$installArguments
        installArguments = $installArguments
    }
    player = $player
    login = $login
    fastCheck = $fastCheck
    excludedCredentials = @("appId", "privateKey")
}

Write-NcmSetupResult -Value $result -AsJson ([bool]$Json) -ShouldCompressJson ([bool]$CompressJson)
