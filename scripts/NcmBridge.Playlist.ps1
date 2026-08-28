<#
主要作用：封装程序专用歌单的查找、创建、修改和曲目顺序处理。
输入：歌单标识、名称、曲目 ID、标签及 ncm-cli 响应对象。
输出：远端歌单对象、操作响应或为保持顺序转换后的曲目 ID 数组。
#>

$ErrorActionPreference = "Stop"

<#
主要作用：读取当前账号创建的歌单集合。
输入：无；通过 ncm-cli 查询远端数据。
输出：创建歌单对象数组。
#>
function Get-CreatedPlaylists {
    $response = Invoke-NcmCliJson -Arguments @("playlist", "created", "--limit", "500", "--offset", "0", "--output", "json")
    Assert-NcmCliOk -Response $response -Message "Failed to list created playlists"

    if ($null -ne $response.data.records) { return @($response.data.records) }
    @($response.data)
}

<#
主要作用：从已创建歌单中按名称寻找目标歌单。
输入：歌单名称。
输出：匹配的歌单对象；未找到时返回 null。
#>
function Find-CreatedPlaylistByName {
    param([Parameter(Mandatory = $true)][string]$Name)

    Get-CreatedPlaylists |
        Where-Object { $_.name -eq $Name } |
        Select-Object -First 1
}

<#
主要作用：从已创建歌单中按加密 ID 或原始 ID 识别目标。
输入：加密歌单 ID 与原始数字歌单 ID。
输出：匹配的歌单对象；未找到时返回 null。
#>
function Find-CreatedPlaylistByIds {
    param(
        [string]$EncryptedId = "",
        [string]$OriginalId = ""
    )

    Get-CreatedPlaylists |
        Where-Object {
            (-not [string]::IsNullOrWhiteSpace($EncryptedId) -and "$($_.id)" -eq $EncryptedId) -or
            (-not [string]::IsNullOrWhiteSpace($OriginalId) -and "$($_.originalId)" -eq $OriginalId)
        } |
        Select-Object -First 1
}

<#
主要作用：根据本地绑定条目在远端创建歌单中定位对应项。
输入：已创建歌单数组与本地歌单条目。
输出：匹配的远端歌单对象；未找到时返回 null。
#>
function Find-CreatedPlaylistByEntry {
    param(
        [Parameter(Mandatory = $true)][array]$CreatedPlaylists,
        [Parameter(Mandatory = $true)][object]$Entry
    )

    $CreatedPlaylists |
        Where-Object {
            ($Entry.encryptedId -and "$($_.id)" -eq "$($Entry.encryptedId)") -or
            ($Entry.originalId -and "$($_.originalId)" -eq "$($Entry.originalId)")
        } |
        Select-Object -First 1
}

<#
主要作用：判断给定歌单绑定是否仍属于当前账号创建的歌单。
输入：本地歌单条目对象。
输出：布尔值，true 表示远端创建歌单中存在该条目。
#>
function Test-BridgePlaylistIsCreated {
    param([Parameter(Mandatory = $true)][object]$Playlist)

    $createdPlaylists = Get-CreatedPlaylists
    [bool](Find-CreatedPlaylistByEntry -CreatedPlaylists $createdPlaylists -Entry $Playlist)
}

<#
主要作用：获取一个歌单的完整远端详情。
输入：歌单加密 ID。
输出：歌单详情对象；查询失败时抛出异常。
#>
function Get-PlaylistDetail {
    param([Parameter(Mandatory = $true)][string]$EncryptedId)

    $response = Invoke-NcmCliJson -Arguments @("playlist", "get", "--playlistId", $EncryptedId, "--output", "json")
    Assert-NcmCliOk -Response $response -Message "Failed to get playlist detail"
    $response.data
}

<#
主要作用：修改远端歌单名称。
输入：歌单加密 ID 与新名称。
输出：ncm-cli 的成功响应对象。
#>
function Rename-Playlist {
    param(
        [Parameter(Mandatory = $true)][string]$EncryptedId,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $response = Invoke-NcmCliJson -Arguments @("playlist", "updateName", "--playlistId", $EncryptedId, "--name", $Name, "--output", "json")
    Assert-NcmCliOk -Response $response -Message "Failed to update playlist name"
}

<#
主要作用：在远端创建新的程序专用歌单。
输入：新歌单名称。
输出：新建歌单对象。
#>
function New-BridgePlaylist {
    param([Parameter(Mandatory = $true)][string]$Name)

    $response = Invoke-NcmCliJson -Arguments @("playlist", "create", "--playlistName", $Name, "--output", "json")
    Assert-NcmCliOk -Response $response -Message "Failed to create playlist '$Name'"

    $created = Find-CreatedPlaylistByName -Name $Name
    if (-not $created) {
        throw "Playlist '$Name' was created but could not be found in created playlists."
    }

    $created
}

<#
主要作用：执行歌单曲目或标签的统一控制操作。
输入：操作类型、歌单 ID、歌曲 ID、曲目 ID 与标签数组。
输出：ncm-cli 的歌单控制响应对象。
#>
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
        throw "Encrypted playlist ID cannot be empty."
    }

    $arguments = @("playlist", $Action, "--playlistId", "$PlaylistId")

    switch ($Action) {
        "add" {
            $validSongIds = @($SongIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($validSongIds.Count -eq 0) { throw "add requires at least one encrypted song ID." }
            $arguments += @("--songIdList", "$(ConvertTo-Json -InputObject @($validSongIds) -Compress)")
        }

        "remove" {
            $validSongIds = @($SongIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($validSongIds.Count -eq 0) { throw "remove requires at least one encrypted song ID." }
            $arguments += @("--songIdList", "$(ConvertTo-Json -InputObject @($validSongIds) -Compress)")
        }

        "reorder" {
            $validTrackIds = @($TrackIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($validTrackIds.Count -eq 0) { throw "reorder requires a full encrypted song ID order list." }
            $arguments += @("--trackIds", "$(ConvertTo-Json -InputObject @($validTrackIds) -Compress)")
        }

        "updateTags" {
            $validTags = @($Tags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($validTags.Count -eq 0 -or $validTags.Count -gt 3) { throw "updateTags requires 1 to 3 tags." }
            $arguments += @("--tags", "$(ConvertTo-Json -InputObject @($validTags) -Compress)")
        }
    }

    $arguments += @("--output", "json")
    Invoke-NcmCliJson -Arguments $arguments
}

<#
主要作用：将目标曲目顺序转换为适合远端头插行为的提交顺序。
输入：用户期望的歌曲加密 ID 数组。
输出：倒序后的歌曲 ID 数组，使最终歌单顺序保持用户指定顺序。
#>
function ConvertTo-NcmBridgeInsertOrder {
    param(
        [Parameter(Mandatory = $true)][string[]]$SongIds
    )

    $values = @($SongIds)
    $reversed = New-Object System.Collections.Generic.List[string]
    for ($index = $values.Count - 1; $index -ge 0; $index--) {
        $reversed.Add("$($values[$index])")
    }

    @($reversed)
}
