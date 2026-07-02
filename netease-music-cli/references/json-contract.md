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

- `success`: boolean action result.
- `action`: stable action name.
- `code`: stable machine code, such as `OK`, `DRY_RUN`, `URL_LAUNCHED`, `VERIFIED`, `NOT_VERIFIED`.
- `message`: short human-readable summary.
- `dryRun`: present when preview mode is meaningful.
- `verified`: present for playback actions. Only SMTC can set this to `true`.

## Playback Rule

`orpheus://` launch success never proves playback changed. Playback is verified only when SMTC returns the expected title, artist, and `Playing` status.

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
