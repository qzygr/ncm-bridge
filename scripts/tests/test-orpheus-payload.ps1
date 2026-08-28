<#
主要作用：保留旧 payload 测试入口，并转调 Orpheus dry-run 测试。
输入：可选 Json 开关。
输出：test-orpheus-dryrun.ps1 的原始测试输出和退出码。
#>

param([switch]$Json)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "test-orpheus-dryrun.ps1"
$arguments = @("-ExecutionPolicy", "Bypass", "-File", $script)
if ($Json) { $arguments += "-Json" }
& powershell @arguments
exit $LASTEXITCODE
