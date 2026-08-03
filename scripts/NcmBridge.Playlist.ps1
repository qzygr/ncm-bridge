$ErrorActionPreference = "Stop"

function Get-CreatedPlaylists {
    $response = Invoke-NcmCliJson -Arguments @("playlist", "created", "--limit", "500", "--offset", "0", "--output", "json")
    Assert-NcmCliOk -Response $response -Message "Failed to list created playlists"

    if ($null -ne $response.data.records) { return @($response.data.records) }
    @($response.data)
}

function Find-CreatedPlaylistByName {
    param([Parameter(Mandatory = $true)][string]$Name)

    Get-CreatedPlaylists |
        Where-Object { $_.name -eq $Name } |
        Select-Object -First 1
}

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

function Test-BridgePlaylistIsCreated {
    param([Parameter(Mandatory = $true)][object]$Playlist)

    $createdPlaylists = Get-CreatedPlaylists
    [bool](Find-CreatedPlaylistByEntry -CreatedPlaylists $createdPlaylists -Entry $Playlist)
}

function Get-PlaylistDetail {
    param([Parameter(Mandatory = $true)][string]$EncryptedId)

    $response = Invoke-NcmCliJson -Arguments @("playlist", "get", "--playlistId", $EncryptedId, "--output", "json")
    Assert-NcmCliOk -Response $response -Message "Failed to get playlist detail"
    $response.data
}

function Rename-Playlist {
    param(
        [Parameter(Mandatory = $true)][string]$EncryptedId,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $response = Invoke-NcmCliJson -Arguments @("playlist", "updateName", "--playlistId", $EncryptedId, "--name", $Name, "--output", "json")
    Assert-NcmCliOk -Response $response -Message "Failed to update playlist name"
}

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
