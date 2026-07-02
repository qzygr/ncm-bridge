# JSON Contract

Agent-facing scripts return a small, stable envelope:

```json
{
  "success": true,
  "action": "status",
  "code": "OK",
  "message": "Human-readable summary"
}
```

## Common Fields

- `success`: boolean action result. For launch actions, `true` can mean the protocol URL was previewed or launched successfully; it does not prove playback changed unless `verified` is also `true`.
- `action`: stable action name.
- `code`: stable machine code. See [Code Values](#code-values).
- `message`: short human-readable summary.
- `dryRun`: boolean preview marker. When `true`, no remote write or real playback launch should be assumed.
- `verified`: boolean playback marker. Only SMTC verification can set this to `true`; `orpheus://` success, dry-run payload generation, or process launch success must leave it `false`.

## Code Values

| Code | Meaning |
|---|---|
| `OK` | The action completed without a special preview, launch, or playback-verification state. Used by status, search, repair, theme update, and playlist write flows. |
| `MISSING` | Status found a configured playlist entry that is not currently healthy or resolvable. |
| `DRY_RUN` | A multi-step preview completed without remote writes or real playback, such as theme preview or `playTheme -DryRun`. |
| `URL_PREVIEWED` | An `orpheus://` protocol URL was generated in dry-run mode. It was not launched and playback was not verified. |
| `URL_LAUNCHED` | An `orpheus://` protocol URL was launched. This confirms only that the launch path was attempted successfully, not that the client started playing the target. |
| `VERIFIED` | SMTC reported the expected playback state: matching title, matching artist, and `Playing`. This is the only code that proves playback changed to the expected target. |
| `NOT_VERIFIED` | SMTC did not report the expected playback state within the verification attempts. The launch may have happened, but the playback result is not proven. |

## Playback Rule

`orpheus://` launch success never proves playback changed. Playback is verified only when SMTC returns the expected title, artist, and `Playing` status.

For playback actions:

- `success: true` with `code: URL_LAUNCHED` means the protocol URL launch path completed, but playback remains unverified.
- `success: true` with `code: VERIFIED` means SMTC verified the expected playback.
- `success: false` with `code: NOT_VERIFIED` means SMTC verification failed or timed out.
- `dryRun: true` always means no playback verification happened.
- `verified: true` must only appear after SMTC verification succeeds.

## Search Records

`searchSong` returns compact records:

```json
{
  "name": "Eclipse",
  "artists": ["Aimer"],
  "originalId": "2694779693",
  "encryptedId": "C9E8705B7783589DB2A3A80CADA71216",
  "album": "Eclipse",
  "duration": 235264
}
```

Use `encryptedId` for playlist edits. Use `originalId` for `playSong`.
