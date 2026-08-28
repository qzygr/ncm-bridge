<#
主要作用：保留旧命令名兼容性，并转调快速统一入口测试。
输入：可选 Json 开关。
输出：test-invoke-fast.ps1 的原始测试输出和退出码。
#>

param([switch]$Json)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "test-invoke-fast.ps1"
$arguments = @("-ExecutionPolicy", "Bypass", "-File", $script)
if ($Json) { $arguments += "-Json" }
& powershell @arguments
exit $LASTEXITCODE
