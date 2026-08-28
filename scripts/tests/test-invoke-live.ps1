<#
主要作用：兼容旧的 live 测试命令名，并转调在线或真实播放测试。
输入：Json 与 IncludePlayback 开关。
输出：对应分层测试的原始输出和退出码。
#>

param([switch]$Json, [switch]$IncludePlayback)

$scriptName = if ($IncludePlayback) { "test-playback.ps1" } else { "test-online.ps1" }
$script = Join-Path $PSScriptRoot $scriptName
$arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script)
if ($Json) { $arguments += "-Json" }
& powershell @arguments
exit $LASTEXITCODE
