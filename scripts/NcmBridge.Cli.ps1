<#
主要作用：封装 ncm-cli 的登录检查、JSON 调用和结果校验。
输入：调用方传入的动作名称、命令行参数与 ncm-cli 返回内容。
输出：标准化的登录诊断对象、解析后的 JSON 对象或明确异常。
#>

$ErrorActionPreference = "Stop"

<#
主要作用：判断某个桥接动作是否必须先确认 ncm-cli 已登录。
输入：统一入口的动作名称。
输出：布尔值，true 表示该动作需要登录前置检查。
#>
function Test-NcmBridgeActionRequiresLogin {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [bool]$DryRun = $false,
        [bool]$Verify = $false
    )

    switch ($Action) {
        "status" { return $true }
        "repair" { return $true }
        "pruneMissing" { return $true }
        "searchSong" { return $true }
        "validateReplaceTracks" { return $true }
        "replaceTracks" { return $true }
        "playTheme" { return $true }
        "setTheme" { return -not $DryRun }
        "verifyPlayback" { return $true }
        "playSong" { return $Verify -and -not $DryRun }
        default { return $false }
    }
}

<#
主要作用：从 ncm-cli 的混合控制台输出中提取并解析有效 JSON。
输入：原始输出对象数组与用于错误说明的调用上下文。
输出：解析后的 JSON 对象；未找到有效 JSON 时抛出包含原始输出的异常。
#>
function ConvertFrom-NcmCliJsonOutput {
    param(
        [Parameter(Mandatory = $true)][object[]]$Output,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $rawText = (@($Output) -join "`n").Trim()
    if (-not $rawText) {
        throw "$Context returned no output."
    }

    try {
        return $rawText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # ncm-cli 可能在 JSON 响应前输出升级提示，继续定位 JSON 起点。
    }

    $objectStart = $rawText.IndexOf("{")
    $arrayStart = $rawText.IndexOf("[")
    $jsonStart = $objectStart
    if ($arrayStart -ge 0 -and ($objectStart -lt 0 -or $arrayStart -lt $objectStart)) {
        $jsonStart = $arrayStart
    }
    if ($jsonStart -lt 0) {
        throw "$Context output does not contain JSON: $rawText"
    }

    $jsonText = $rawText.Substring($jsonStart)
    try {
        return $jsonText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "$Context JSON parsing failed: $jsonText"
    }
}

<#
主要作用：执行 ncm-cli login --check 并将原始输出转换为对象。
输入：无；依赖系统 PATH 中的 ncm-cli。
输出：登录检查的 JSON 对象；无法解析时返回包含错误信息的对象。
#>
function Invoke-NcmCliLoginCheck {
    $command = Get-Command "ncm-cli" -ErrorAction Stop
    $raw = & ncm-cli login --check
    $parsed = ConvertFrom-NcmCliJsonOutput -Output @($raw) -Context "ncm-cli login --check"
    [pscustomobject]@{
        success = [bool]$parsed.success
        message = if ($parsed.message) { "$($parsed.message)" } else { $null }
        commandPath = "$($command.Source)"
    }
}

<#
主要作用：构造统一的“需要登录”结果，避免将隐藏命令误判为功能缺失。
输入：可选的登录检查结果对象。
输出：code 为 LOGIN_REQUIRED 的标准结果对象。
#>
function New-NcmCliLoginRequiredResult {
    param(
        [object]$LoginStatus = $null,
        [string]$ActionName = "loginCheck"
    )

    [pscustomobject]@{
        success = $false
        action = $ActionName
        code = "LOGIN_REQUIRED"
        message = if ($LoginStatus -and $LoginStatus.message) { "$($LoginStatus.message)" } else { "ncm-cli login is required before this action." }
        login = [pscustomobject]@{
            checked = $true
            success = $false
            message = if ($LoginStatus -and $LoginStatus.message) { "$($LoginStatus.message)" } else { $null }
        }
        nextAction = "Start desktop login flow and wait for QR login to complete before retrying."
        loginCommand = "Start-Process 'powershell' -ArgumentList '-NoExit', '-Command', 'ncm-cli login --background'"
    }
}

<#
主要作用：断言 ncm-cli 已登录，否则中止需要远端能力的调用。
输入：无；读取当前 ncm-cli 登录状态。
输出：成功时返回登录结果；失败时抛出或返回登录限制对象。
#>
function Assert-NcmCliLoggedIn {
    $status = Invoke-NcmCliLoginCheck
    if (-not $status.success) {
        $result = New-NcmCliLoginRequiredResult -LoginStatus $status
        throw "$($result.code): $($result.message)"
    }

    $status
}

<#
主要作用：安全执行 ncm-cli 并解析其 JSON 输出，处理 Windows 参数转义。
输入：ncm-cli 的字符串参数数组，可包含空字符串。
输出：解析后的 JSON 响应对象；命令或解析失败时抛出异常。
#>
function Invoke-NcmCliJson {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Arguments)

    $null = Assert-NcmCliLoggedIn

    $command = Get-Command "ncm-cli" -ErrorAction SilentlyContinue
    $cliPath = $null
    if ($command -and $command.Source) {
        $commandDir = Split-Path -Parent $command.Source
        $candidatePath = Join-Path $commandDir "node_modules\@music163\ncm-cli\dist\index.js"
        if (Test-Path -LiteralPath $candidatePath) {
            $cliPath = $candidatePath
        }
    }

    if (-not $cliPath) {
        $fallbackPath = Join-Path $env:APPDATA "npm\node_modules\@music163\ncm-cli\dist\index.js"
        if (Test-Path -LiteralPath $fallbackPath) {
            $cliPath = $fallbackPath
        }
    }

    if (-not $cliPath) {
        throw "ncm-cli entry point was not found. Install @music163/ncm-cli globally."
    }

    function ConvertTo-WindowsArgument {
        param([string]$Value)

        if ($Value -eq "") {
            return '""'
        }

        if ($Value -notmatch '[\s"]') {
            return $Value
        }

        $builder = [System.Text.StringBuilder]::new()
        [void]$builder.Append('"')
        $backslashCount = 0

        foreach ($char in $Value.ToCharArray()) {
            if ($char -eq '\') {
                $backslashCount++
                continue
            }

            if ($char -eq '"') {
                [void]$builder.Append(('\' * (($backslashCount * 2) + 1)))
                [void]$builder.Append('"')
                $backslashCount = 0
                continue
            }

            if ($backslashCount -gt 0) {
                [void]$builder.Append(('\' * $backslashCount))
                $backslashCount = 0
            }
            [void]$builder.Append($char)
        }

        if ($backslashCount -gt 0) {
            [void]$builder.Append(('\' * ($backslashCount * 2)))
        }
        [void]$builder.Append('"')
        $builder.ToString()
    }

    $allArguments = @($cliPath) + $Arguments
    $argumentText = ($allArguments | ForEach-Object { ConvertTo-WindowsArgument -Value "$_" }) -join " "
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = "node"
    $processInfo.Arguments = $argumentText
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = [System.Diagnostics.Process]::Start($processInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($stderr) {
        throw "ncm-cli stderr: $stderr"
    }
    if ($process.ExitCode -ne 0) {
        throw "ncm-cli exited with code $($process.ExitCode)`n$stdout"
    }
    if (-not $stdout.Trim()) {
        throw "ncm-cli returned no output: $($Arguments -join ' ')"
    }

    try {
        return ConvertFrom-NcmCliJsonOutput -Output @($stdout) -Context "ncm-cli $($Arguments -join ' ')"
    }
    catch {
        throw "ncm-cli output is not valid JSON: $stdout"
    }
}

<#
主要作用：检查 ncm-cli 响应是否表示业务成功。
输入：ncm-cli 响应对象与调用失败时使用的错误提示。
输出：成功时返回原响应；失败时抛出带上下文的异常。
#>
function Assert-NcmCliOk {
    param(
        [Parameter(Mandatory = $true)][object]$Response,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Response.code -ne 200) {
        throw "${Message}: $($Response.message)"
    }
}
