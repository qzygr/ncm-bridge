# OrpheusControl.ps1
# 网易云音乐本地服务控制模块（基于 orpheus:// 协议）
# 用法：. .\OrpheusControl.ps1    （dot-source 加载）
#       OrpheusControl -Json '{"cmd":"next"}'
#       Invoke-OrpheusCommand -Name "next"

# ============================================================
# 核心函数：将 JSON 指令编码为 orpheus:// 协议 URL 并执行
# 编码方式：UTF-8 → 标准 Base64（含尾部 = 填充）
# ============================================================
function OrpheusControl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json,

        [switch]$DryRun
    )

    # 校验 JSON 合法性
    try {
        $null = $Json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Error "[OrpheusControl] 无效的 JSON 输入: $_"
        return
    }

    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $base64 = [Convert]::ToBase64String($bytes)
    $url    = "orpheus://$base64"

    if ($DryRun) {
        Write-Host "[DryRun] $url"
    }
    else {
        try {
            Start-Process $url -ErrorAction Stop
            Write-Host "[OrpheusControl] 指令已发送: $url"
        }
        catch {
            Write-Error "[OrpheusControl] 无法启动协议处理器，请确认网易云客户端已运行且 orpheus:// 协议已注册。"
        }
    }

    return $url
}

# ============================================================
# 便捷函数：从 JSON 注册表按名称查找命令并执行
# ============================================================
function Invoke-OrpheusCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [hashtable]$Params = @{},

        [string]$RegistryPath = $null,

        [switch]$DryRun
    )

    if (-not $RegistryPath) {
        $RegistryPath = Join-Path $PSScriptRoot "orpheus_commands.json"
    }

    if (-not (Test-Path $RegistryPath)) {
        Write-Error "[Invoke-OrpheusCommand] 注册表未找到: $RegistryPath"
        return
    }

    try {
        $registry = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Error "[Invoke-OrpheusCommand] JSON 解析失败: $_"
        return
    }

    $cmdDef = $registry.commands | Where-Object { $_.name -eq $Name }
    if (-not $cmdDef) {
        $available = ($registry.commands | ForEach-Object { $_.name }) -join ', '
        Write-Error "[Invoke-OrpheusCommand] 未知命令 '$Name'。可用: $available"
        return
    }

    # 将 payload 序列化为紧凑 JSON
    $payload = $cmdDef.payload | ConvertTo-Json -Compress

    # 替换占位符（$value, $id 等）
    foreach ($key in $Params.Keys) {
        $placeholder = "`"`$$key`""
        $replacement = if ($Params[$key] -is [string]) {
            "`"$($Params[$key])`""
        } else {
            $Params[$key].ToString()
        }
        $payload = $payload.Replace($placeholder, $replacement)
    }

    if ($payload -match '\$\w+') {
        Write-Error "[Invoke-OrpheusCommand] 缺少必填参数，仍有未替换的占位符: $($matches.Values)"
        return
    }

    OrpheusControl -Json $payload -DryRun:$DryRun
}

# ============================================================
# 数据层辅助函数：调用 ncm-cli 并保留参数边界
# 用途：避免 PowerShell/cmd 对 JSON 数组参数做错误转义
# ============================================================
function Invoke-NcmCliJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $cliPath = Join-Path $env:APPDATA "npm\node_modules\@music163\ncm-cli\dist\index.js"
    if (-not (Test-Path $cliPath)) {
        Write-Verbose "[Invoke-NcmCliJson] Checked ncm-cli path: $cliPath"
        Write-Error "[Invoke-NcmCliJson] ncm-cli 入口未找到，请确认已全局安装 @music163/ncm-cli。"
        return $null
    }

    function ConvertTo-WindowsArgument {
        param([string]$Value)

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
                [void]$builder.Append('\' * (($backslashCount * 2) + 1))
                [void]$builder.Append('"')
                $backslashCount = 0
                continue
            }

            if ($backslashCount -gt 0) {
                [void]$builder.Append('\' * $backslashCount)
                $backslashCount = 0
            }
            [void]$builder.Append($char)
        }

        if ($backslashCount -gt 0) {
            [void]$builder.Append('\' * ($backslashCount * 2))
        }
        [void]$builder.Append('"')
        return $builder.ToString()
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
    $exitCode = $process.ExitCode

    if ($stderr) {
        Write-Error "[Invoke-NcmCliJson] ncm-cli stderr: $stderr"
    }

    if ($exitCode -ne 0) {
        Write-Error "[Invoke-NcmCliJson] ncm-cli exited with code $exitCode`n$stdout"
        return $null
    }
    if (-not $stdout.Trim()) {
        return $null
    }

    try {
        return $stdout | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Error "[Invoke-NcmCliJson] ncm-cli 输出不是合法 JSON: $_`n$stdout"
        return $null
    }
}

# ============================================================
# 数据层辅助函数：通过原始歌单 ID 查找加密歌单 ID
# ============================================================
function Resolve-NcmPlaylistEncryptedId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OriginalId,

        [int]$Limit = 500
    )

    foreach ($scope in @("created", "collected")) {
        $result = Invoke-NcmCliJson -Arguments @("playlist", $scope, "--limit", "$Limit", "--output", "json")
        if ($null -eq $result -or $null -eq $result.data) {
            continue
        }

        $playlists = if ($null -ne $result.data.records) { $result.data.records } else { $result.data }
        $match = $playlists | Where-Object { "$($_.originalId)" -eq "$OriginalId" } | Select-Object -First 1
        if ($match) {
            return $match.id
        }
    }

    Write-Error "[Resolve-NcmPlaylistEncryptedId] 未找到原始歌单 ID: $OriginalId"
    return $null
}

# ============================================================
# 数据层辅助函数：统一处理歌单控制命令中的 JSON 数组参数
# 支持：add/remove/reorder/updateTags
# ============================================================
function Invoke-NcmPlaylistControl {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("add", "remove", "reorder", "updateTags")]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$PlaylistId,

        [string[]]$SongIds = @(),

        [string[]]$TrackIds = @(),

        [string[]]$Tags = @()
    )

    if ([string]::IsNullOrWhiteSpace($PlaylistId)) {
        Write-Error "[Invoke-NcmPlaylistControl] 加密歌单 ID 不能为空。"
        return
    }

    $arguments = @("playlist", $Action, "--playlistId", "$PlaylistId")

    switch ($Action) {
        "add" {
            $validSongIds = @($SongIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($validSongIds.Count -eq 0) {
                Write-Error "[Invoke-NcmPlaylistControl] add 需要至少一个加密歌曲 ID。"
                return
            }

            $songIdList = ConvertTo-Json -InputObject @($validSongIds) -Compress
            $arguments += @("--songIdList", "$songIdList")
        }

        "remove" {
            $validSongIds = @($SongIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($validSongIds.Count -eq 0) {
                Write-Error "[Invoke-NcmPlaylistControl] remove 需要至少一个加密歌曲 ID。"
                return
            }

            $songIdList = ConvertTo-Json -InputObject @($validSongIds) -Compress
            $arguments += @("--songIdList", "$songIdList")
        }

        "reorder" {
            $validTrackIds = @($TrackIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($validTrackIds.Count -eq 0) {
                Write-Error "[Invoke-NcmPlaylistControl] reorder 需要完整的加密歌曲 ID 顺序列表。"
                return
            }

            $trackIdList = ConvertTo-Json -InputObject @($validTrackIds) -Compress
            $arguments += @("--trackIds", "$trackIdList")
        }

        "updateTags" {
            $validTags = @($Tags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($validTags.Count -eq 0 -or $validTags.Count -gt 3) {
                Write-Error "[Invoke-NcmPlaylistControl] updateTags 需要 1 到 3 个标签。"
                return
            }

            $tagList = ConvertTo-Json -InputObject @($validTags) -Compress
            $arguments += @("--tags", "$tagList")
        }
    }

    $arguments += @("--output", "json")
    Invoke-NcmCliJson -Arguments $arguments
}

# ============================================================
# 便捷函数：列出本模块文件内定义的所有函数
# ============================================================
function Get-OrpheusControlFunctions {
    param(
        [string]$Path = $null
    )

    if (-not $Path) {
        $Path = $PSCommandPath
    }
    if (-not $Path) {
        $Path = Join-Path $PSScriptRoot "OrpheusControl.ps1"
    }
    if (-not (Test-Path $Path)) {
        Write-Error "模块文件未找到: $Path"
        return
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        Write-Error "模块文件解析失败: $($errors[0].Message)"
        return
    }

    $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        ForEach-Object {
            [pscustomobject]@{
                name = $_.Name
                line = $_.Extent.StartLineNumber
            }
        } |
        Sort-Object line |
        Format-Table name, line -AutoSize
}

# ============================================================
# 便捷函数：列出所有可用 Orpheus 协议命令
# ============================================================
function Get-OrpheusCommands {
    param(
        [string]$RegistryPath = $null
    )

    if (-not $RegistryPath) {
        $RegistryPath = Join-Path $PSScriptRoot "orpheus_commands.json"
    }

    if (-not (Test-Path $RegistryPath)) {
        Write-Error "注册表未找到: $RegistryPath"
        return
    }

    $registry = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $registry.commands | Format-Table name, description -AutoSize
}
