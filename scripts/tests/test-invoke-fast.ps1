<#
主要作用：兼容旧的 fast 测试命令名，并转调前置完整性测试。
输入：可选 Json 开关。
输出：test-preflight.ps1 的原始测试输出和退出码。
#>

param([switch]$Json)

$script = Join-Path $PSScriptRoot "test-preflight.ps1"
$arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script)
if ($Json) { $arguments += "-Json" }
& powershell @arguments
exit $LASTEXITCODE
