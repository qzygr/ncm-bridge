$ErrorActionPreference = "Stop"

function Get-NcmTextWidth {
    param([Parameter(Mandatory = $true)][string]$Text)

    $width = 0
    foreach ($char in $Text.ToCharArray()) {
        if ([int][char]$char -le 0x7F) { $width += 1 } else { $width += 2 }
    }
    $width
}

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
