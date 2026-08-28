<#
主要作用：在确认未登录后启动可见的 ncm-cli 扫码登录窗口。
输入：Json 与 CompressJson 输出开关。
输出：已登录时返回 OK；未登录时仅在登录窗口进程已启动后返回 LOGIN_WINDOW_STARTED。

说明：本脚本不等待用户扫码完成，也不执行搜索、歌单、播放或其他联网动作。
#>

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$CompressJson
)

$ErrorActionPreference = "Stop"
$scriptsRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $scriptsRoot "modules\NcmBridge.Cli.ps1")

<#
主要作用：按普通对象或 JSON 形式输出登录启动结果。
输入：结果对象、JSON 开关与压缩 JSON 开关。
输出：控制台结果对象或 JSON 文本。
#>
function Write-NcmLoginStartResult {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [bool]$AsJson,
        [bool]$ShouldCompressJson
    )

    if ($AsJson) {
        $Value | ConvertTo-Json -Depth 6 -Compress:$ShouldCompressJson
    }
    else {
        $Value
    }
}

$login = Invoke-NcmCliLoginCheck
if ($login.success) {
    $result = [pscustomobject]@{
        success = $true
        action = "startLogin"
        code = "OK"
        message = "ncm-cli is already logged in."
        login = $login
        loginWindowStarted = $false
        loginWindowProcessId = $null
    }
}
else {
    $window = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", "ncm-cli login --background" `
        -WindowStyle Normal `
        -PassThru
    Start-Sleep -Milliseconds 300
    if ($window.HasExited) {
        throw "The ncm-cli login window exited before it could be presented."
    }

    $result = [pscustomobject]@{
        success = $true
        action = "startLogin"
        code = "LOGIN_WINDOW_STARTED"
        message = "ncm-cli login window started. Complete QR login in the visible window, then run ncm-cli login --check."
        login = $login
        loginWindowStarted = $true
        loginWindowProcessId = $window.Id
    }
}

Write-NcmLoginStartResult -Value $result -AsJson ([bool]$Json) -ShouldCompressJson ([bool]$CompressJson)
