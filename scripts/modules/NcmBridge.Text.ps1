<#
主要作用：提供歌单显示名称与中英文文本宽度处理。
输入：待计算的文本、主题标题与角色名称。
输出：显示宽度整数或格式化后的歌单名称。
#>

$ErrorActionPreference = "Stop"

<#
主要作用：按全角字符占两格、半角字符占一格计算显示宽度。
输入：任意文本字符串。
输出：文本显示宽度整数。
#>
function Get-NcmTextWidth {
    param([Parameter(Mandatory = $true)][string]$Text)

    $width = 0
    foreach ($char in $Text.ToCharArray()) {
        if ([int][char]$char -le 0x7F) { $width += 1 } else { $width += 2 }
    }
    $width
}

<#
主要作用：生成带可选角色前缀的程序专用歌单名称。
输入：歌单标题与可选角色名称。
输出：例如【角色】主题的显示名称字符串。
#>
function Get-BridgePlaylistName {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$RoleName = ""
    )

    $trimmedTitle = $Title.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedTitle)) {
        throw "Playlist title cannot be empty."
    }

    $leftBracket = [char]0x3010
    $rightBracket = [char]0x3011
    $rightBracketIndex = $trimmedTitle.IndexOf($rightBracket)
    if ($trimmedTitle.StartsWith($leftBracket) -and $rightBracketIndex -gt 1 -and $rightBracketIndex -lt ($trimmedTitle.Length - 1)) {
        return $trimmedTitle
    }

    $prefixName = if ([string]::IsNullOrWhiteSpace($RoleName)) { "Agent" } else { $RoleName.Trim() }
    "$leftBracket$prefixName$rightBracket$trimmedTitle"
}
