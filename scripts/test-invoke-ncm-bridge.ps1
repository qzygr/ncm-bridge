param([switch]$Json)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "test-invoke-fast.ps1"
$arguments = @("-ExecutionPolicy", "Bypass", "-File", $script)
if ($Json) { $arguments += "-Json" }
& powershell @arguments
exit $LASTEXITCODE
