function New-BridgeHelpResult {
    $actionNames = @(
        "help",
        "diagnose",
        "status",
        "repair",
        "pruneMissing",
        "dryRun",
        "searchSong",
        "playSong",
        "verifyPlayback",
        "playDefault",
        "setTheme",
        "replaceTracks",
        "validateReplaceTracks",
        "playTheme"
    )

    [pscustomobject]@{
        success = $true
        action = "help"
        code = "OK"
        message = "NCM bridge action help."
        usage = "powershell -ExecutionPolicy Bypass -File .\scripts\invoke-ncm-bridge.ps1 -Action <action> [-Json [-CompressJson]]"
        actions = @(
            [pscustomobject]@{
                name = "help"
                purpose = "Return this action catalog and constraints."
                keyParameters = @("Json", "CompressJson")
                writesRemote = $false
                verifiesPlayback = $false
            }
            [pscustomobject]@{
                name = "diagnose"
                purpose = "Check ncm-cli availability, login status, config presence, and optionally SMTC without remote writes."
                keyParameters = @("ConfigPath", "Verify", "Attempts", "RetryDelayMs", "InitialDelayMs")
                writesRemote = $false
                verifiesPlayback = $false
            }
            [pscustomobject]@{
                name = "status"
                purpose = "Read bridge playlist health and summary status."
                keyParameters = @("PlaylistKey", "ConfigPath")
                writesRemote = $false
                verifiesPlayback = $false
            }
            [pscustomobject]@{
                name = "repair"
                purpose = "Repair bridge config bindings."
                keyParameters = @("Prefer", "PruneMissing", "DryRun", "ConfigPath")
                writesRemote = $false
                verifiesPlayback = $false
            }
            [pscustomobject]@{
                name = "pruneMissing"
                purpose = "Prune missing playlist bindings through the repair flow."
                keyParameters = @("Prefer", "DryRun", "ConfigPath")
                writesRemote = $false
                verifiesPlayback = $false
            }
            [pscustomobject]@{
                name = "dryRun"
                purpose = "Compatibility dry-run for orpheus payload generation."
                keyParameters = @()
                writesRemote = $false
                verifiesPlayback = $false
            }
            [pscustomobject]@{
                name = "searchSong"
                purpose = "Search songs and return compact IDs."
                keyParameters = @("Keyword", "ExactTitle", "Artist", "Limit")
                writesRemote = $false
                verifiesPlayback = $false
            }
            [pscustomobject]@{
                name = "playSong"
                purpose = "Launch playback for one original song ID."
                keyParameters = @("OriginalId", "ExpectedTitle", "ExpectedArtist", "Verify", "DryRun", "Attempts", "RetryDelayMs", "InitialDelayMs")
                writesRemote = $false
                verifiesPlayback = $true
            }
            [pscustomobject]@{
                name = "verifyPlayback"
                purpose = "Verify current playback through Windows SMTC."
                keyParameters = @("ExpectedTitle", "ExpectedArtist", "Attempts", "RetryDelayMs", "InitialDelayMs")
                writesRemote = $false
                verifiesPlayback = $true
            }
            [pscustomobject]@{
                name = "playDefault"
                purpose = "Launch playback for the configured bridge playlist."
                keyParameters = @("PlaylistKey", "ConfigPath", "DryRun")
                writesRemote = $false
                verifiesPlayback = $false
            }
            [pscustomobject]@{
                name = "setTheme"
                purpose = "Set the bridge playlist theme."
                keyParameters = @("Theme", "Description", "PlaylistKey", "ConfigPath", "DryRun")
                writesRemote = $true
                verifiesPlayback = $false
            }
            [pscustomobject]@{
                name = "replaceTracks"
                purpose = "Replace bridge playlist tracks."
                keyParameters = @("SongIds", "PlaylistKey", "ConfigPath", "DryRun")
                writesRemote = $true
                verifiesPlayback = $false
            }
            [pscustomobject]@{
                name = "validateReplaceTracks"
                purpose = "Validate track replacement without applying it."
                keyParameters = @("SongIds", "PlaylistKey", "ConfigPath")
                writesRemote = $false
                verifiesPlayback = $false
            }
            [pscustomobject]@{
                name = "playTheme"
                purpose = "Set theme, replace tracks, launch playlist playback, and optionally verify."
                keyParameters = @("Theme", "Description", "SongIds", "PlaylistKey", "ConfigPath", "ExpectedTitle", "ExpectedArtist", "Verify", "DryRun")
                writesRemote = $true
                verifiesPlayback = $true
            }
        )
        parameters = @(
            [pscustomobject]@{
                name = "Action"
                required = $true
                description = "Action dispatcher name."
                values = $actionNames
            }
            [pscustomobject]@{
                name = "Json"
                required = $false
                description = "Return a machine-readable JSON envelope."
            }
            [pscustomobject]@{
                name = "CompressJson"
                required = $false
                description = "Compress JSON to one line; only meaningful with Json."
            }
            [pscustomobject]@{
                name = "ConfigPath"
                required = $false
                description = "Bridge config path; defaults to .ncm-bridge.json at repo root."
            }
            [pscustomobject]@{
                name = "PlaylistKey"
                required = $false
                description = "Bridge playlist key; defaults to default when an action needs a key."
            }
            [pscustomobject]@{
                name = "Keyword"
                requiredFor = @("searchSong")
                description = "Search keyword."
            }
            [pscustomobject]@{
                name = "OriginalId"
                requiredFor = @("playSong")
                description = "Original numeric song ID returned by searchSong.records.originalId."
            }
            [pscustomobject]@{
                name = "SongIds"
                requiredFor = @("replaceTracks", "validateReplaceTracks", "playTheme")
                description = "Encrypted song IDs; comma-separated values are accepted."
            }
            [pscustomobject]@{
                name = "Theme"
                requiredFor = @("setTheme", "playTheme")
                description = "Playlist theme title."
            }
            [pscustomobject]@{
                name = "Verify"
                required = $false
                description = "Run SMTC playback verification after supported playback actions."
            }
            [pscustomobject]@{
                name = "DryRun"
                required = $false
                description = "Preview supported writes or protocol URLs without remote write or real playback."
            }
        )
        constraints = @(
            "Use this script as the Agent entry point for common bridge operations.",
            "Prefer -Json -CompressJson for Agent calls; -CompressJson only changes output when -Json is present.",
            "Check ncm-cli login before interpreting missing commands; logged-out command lists can be incomplete.",
            "diagnose returns LOGIN_REQUIRED instead of treating hidden logged-out commands as version evidence.",
            "Preview real remote writes with -DryRun or validateReplaceTracks before applying changes.",
            "An orpheus:// launch, payload dry-run, or process success does not prove client playback.",
            "Only Windows SMTC verification can set playback verified=true.",
            "playSong requires OriginalId; replaceTracks, validateReplaceTracks, and playTheme require encrypted SongIds.",
            "searchSong clamps Limit to the range 1..20."
        )
    }
}

function ConvertTo-BridgeHelpText {
    param([Parameter(Mandatory = $true)][object]$Value)

    $actionNames = @($Value.actions | ForEach-Object { $_.name })

    @(
        "NCM bridge help",
        "Usage: $($Value.usage)",
        "Actions: $($actionNames -join ', ')",
        "Key params: -Keyword/-ExactTitle/-Artist/-Limit for searchSong; -OriginalId for playSong; -SongIds for track replacement/playTheme; -Theme/-Description for theme actions; -Verify for SMTC verification/diagnostics; -DryRun for previews.",
        "Constraints: check login before command diagnosis; preview remote writes first; orpheus launch/dry-run success does not prove playback; only SMTC can verify playback.",
        "Use -Json or -Json -CompressJson for the full machine-readable envelope."
    )
}
