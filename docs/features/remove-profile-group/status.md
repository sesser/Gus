Issue: #219

# Remove the Profile group: status

Owner: swift-macos-engineer. Branch `feature/remove-profile-group`. Spec: the
PRD (issue #219 body, revised 2026-11-18: RI-1 Reset All clears a stored Look,
RI-2 Standard-family Lightroom profiles not reported) and
[`design.md`](design.md).

State: **Done** (2026-11-18). Every criterion is built and tested or has a
scripted check; what only a person can check is under "For a person".

## Baseline

- 2026-11-18, branch at bd3bb4d (the design commit on `develop` 91e4e1c):
  `swift build` clean, `swift test` 1162 tests in 173 suites passed.

## Steps

| # | Step | State |
|---|---|---|
| 1 | Delete the `raw-lookFlat` and `raw-lookNeutral` goldens (cases, PNGs, fingerprints); the corpus keeps both stacks, built explicitly | Done (ad2c070) |
| 2 | PhotoCore: stored Look kept, never rendered; no Profile group; paste and presets; Reset All; Lightroom mapping; `photocli`. PhotoApp: Profile and Decoder pop-ups, the LibRaw note, strings, debug commands | Done (db14992) |
| 3 | Tests for AC3, AC4, AC6, AC7, AC11, AC12 (`StoredLookTests`) | Done (02c8672) |
| 4 | `PreviewCacheKey.currentPipelineVersion` 13 (R5) | Done (3c18e15) |
| 5 | User guide (design §9), this file | Done |

## Latest results

- `swift build`: clean, no new warnings (the one test warning, in
  `VirtualCopiesTests.swift`, is older than this branch).
- `swift test`: 1176 tests in 174 suites passed (2026-11-18, final run);
  16 tests new in `StoredLookTests`, `RAWDecodeTests.storedLookRendersAsDefault`
  replaces the old Look-contrast test, two Decoder pop-up tests deleted.
- Goldens: every golden but the two deleted passes with no update (AC5).
- `Scripts/build-app.sh`: built. Scripted runs on a copy with the identifier
  `me.sesser.gus.debugtest219` and a scratch library from `photobench generate`
  (2 JPEG, 2 DNG, 100 HEIC) imported with `photobench import`, always with
  `--library-root`. No Gus process left; nothing under the owner's Application
  Support or Caches folders is newer than the scratch bundle.

## R5: the render-hash check

- The render hash covers every enabled operation's parameters, so it covers a
  stored Look. A stack holding one is kept byte for byte (R3), so its render
  hash does not change: `EditStackCorpusTests` still finds `raw-lookFlat` at
  `597736ba…` and `raw-lookNeutral` at `bcaa9121…`, both recorded before this
  branch.
- Its render does change (Neutral and Flat now render as the decoder's
  default: `RAWDecodeTests.storedLookRendersAsDefault`). A preview cached under
  the unchanged hash would keep the old look, so **the version is 13**, a plain
  bump with no carry-over: every preview is made again once.
- Stacks without a stored Look: same hash, same pixels (all goldens pass, no
  update).
- Not done: making the hash ignore a stored Look (the PRD's open question). The
  hash is stored in every `version` row (`editStackHash`, kept in sync on each
  write, compared by `PreviewService` against the loaded stack); changing what
  it covers would leave stored hashes disagreeing with their stacks until each
  photo is written again, and fixing that needs a migration, a non-goal.

## Answers to the PRD's open questions for the engineer

- Does the render hash cover a stored `look`? Yes; the cache version is 13 (above).
- Which goldens render with a Look? Only `raw-lookFlat` and `raw-lookNeutral`
  (deleted). `raw-asShot`, `raw-extendedRange-exposureMinus1` and
  `raw-noiseReduction` hold no `rawDecode` and pass unchanged. The corpus holds
  `look` in `raw-lookFlat`, `raw-lookNeutral` and `everything`; all three are
  kept as the test of R3.
- `RawDefaults`: `offeredDecoderVersions` and `defaultDecoderVersion` existed
  only for the pop-up and are deleted. `decoderVersions` stays (machine
  learning availability). `Adjustments.chooseDecoder`, the editor's
  `chooseDecoder` and `Status.decoderChoiceIsEnabled` are deleted.

## How it is built

- `RawDecode.storedLook: String?` replaces the `Look` enum: read as stored
  (any text, so a value this build never wrote is kept too), written back
  unchanged, never rendered, not described to scripts. `decoderVersion` and the
  legacy machine learning version are as before. The operation belongs to no
  `Group` or `Section`, so a heading's reset, on/off and modified state, presets
  and Copy never touch it.
- `RAWDecodeSettings.boostAmount` stays, documented as measurement only: no
  stack sets it (`AdjustmentRenderer.rawDecodeSettings` no longer does);
  `BaselineLookMeasurementTests` and one white-balance cross-check measure the
  system decoder's own response with it.
- Paste (`Adjustments.pasted(onto:)`) keeps the target's stored decode, on or
  off as it was.
- `AdjustmentPreset(… keepingStoredDecode:)`: the catalog and `.guspreset`
  readers keep a preset's stored decode, so it stays in the stored data through
  rename, move, Include and export (R6); a new preset never carries one.
  Applying one applies nothing from it, except a legacy machine learning
  decoder, which still turns machine learning on (ml-denoise PRD R3, kept by
  R4). That rule used to fire when Profile was among the groups applied; it
  now fires when the preset's stored decode holds the legacy version, which
  only a preset that carried Profile has. Residual difference: a legacy preset
  whose Profile was later unticked in Include, while the old build was still in
  use, now turns machine learning on where it did not. That takes a preset saved
  with the machine learning decoder chosen in Profile before Use machine
  learning existed, then edited in Include; rare, and not tested.
- `Adjustments.resettingAll()` is Reset All's one rule (the loupe's menu and ⋯
  command through `AdjustmentEditor.resetAll`, the grid through
  `BatchActions.resetAllAdjustments`): only unknown operations stay, so the
  stored decode goes with everything else (RI-1).
- Lightroom (`CameraRawMapping.Converter.profile`): no profile sets anything.
  A name outside the Standard family is reported as `.profile` ("Profiles and
  creative looks"); the family is matched by whole name, case and surrounding
  spaces ignored (`standard`, `adobe color`, `adobe standard`, `default`,
  `embedded`), so "Camera Standard" and "Camera Neutral" are reported (design §7
  rule 1). A monochrome name is reported only as black and white.
- `photocli`: `adjustments` lists `rawDecode` with `decoderVersion` only, its
  group and section null (like `crop`); `--set rawDecode.look=…` and
  `--reset rawDecode.look` fail as an unknown parameter (`invalidEdit`, "rawDecode
  has no parameter look", exit 1). `--reset all` clears the stored decode.
- PhotoApp: `DevelopControls` starts at White Balance; `profile`,
  `decoderPopUp`, `lookTitle`, `fallbackDecoderNote` and `FallbackDecoderText`
  deleted; `MachineLearningText.decoderItem` and `decoderDimmedHelp` deleted;
  the debug script loses `adjust look`, `ml decoder` and the `decoder`/`note`
  fields of `print ml`. Catalog entries deleted: Profile, Decoder, Neutral,
  Flat, `%@ (default)`, `%@ (machine learning)`, the dimmed-pop-up tooltip and
  the LibRaw note. "Standard" stays (the Export sheet's sharpening amount uses
  it); its comment now says so.

## Acceptance criteria

| AC | How it is checked | Result |
|---|---|---|
| AC1 | Debug script `buttons`, `print ml` on a DNG (system raw) and a JPEG: Light's first control is the White Balance Mode pop-up ("As Shot"); no Profile, Look or Decoder pop-up; Use machine learning in Noise Reduction. LibRaw photo: the branch that showed the note is deleted; no LibRaw-only file in the scratch library, so by eye (M1) | Pass (scripted); M1 open |
| AC2 | `RAWDecodeTests.storedLookRendersAsDefault` (flat, neutral; system decoder; byte for byte with the same stack without it); `LibRawDecoderTests` (`storedLook = "flat"` renders as plain); `AdjustmentsModelTests` (boost never set; the average of a stored Flat equals as shot) | Pass |
| AC3 | `StoredLookTests`: an edit, a heading's reset and on/off, paste, a preset; byte-for-byte round trip; a batch write; `photocli develop`, undo and redo writes; `EditStackCorpusTests`. Debug script: an exposure edit on a photo with a stored Flat keeps `"look":"flat"` | Pass |
| AC4 | `MachineLearningNoiseReductionTests` (all, unchanged in substance); `StoredLookTests.storedDecoderVersionRenders` (a stored `7.dng` reaches the decoder; turned off, it does not, as before) | Pass |
| AC5 | Every golden passes with no update; version 13 (R5 above); `StoredLookTests.pipelineVersion` | Pass |
| AC6 | `StoredLookTests.oldPresetsInTheCatalog` (groups "light,profile" read as Light; the stored Look kept through a rename; applying changes only Tone), `oldPresetFiles`, `noProfileGroup`; `MachineLearningNoiseReductionTests.storedDecodeNeverTurnsItOff`, `legacyPresetTurnsItOn` | Pass |
| AC7 | `StoredLookTests` AC7 tests (Flat, Neutral, Camera Neutral, Camera Standard, Adobe Landscape, Adobe Vivid, a creative look reported; Standard, Adobe Color, Adobe Standard, default, Embedded not; as `CameraProfile` and as `Look`); `PresetTests.convertsTemplates` | Pass |
| AC8 | `CommandTests.setParsing` (`rawDecode.look=flat` refused), `adjustmentsListsEveryModule`; `photocli render --set rawDecode.look=flat` on the scratch library: exit 1, `invalidEdit` | Pass |
| AC9 | Commit ad2c070, on its own | Pass |
| AC10 | Search of `docs/USER_GUIDE.md` for "Profile", "Look" and "Decoder pop-up": none. Lowercase "profile" remains only in the Lightroom list (design §9.8) and `photobench`'s "profiles import" | Pass |
| AC11 | `StoredLookTests.historyRevertAndUndo` | Pass |
| AC12 | `StoredLookTests.resetAllRemovesIt` (a Look, a Look with a decoder version, a decoder version alone), `resetAllKeepsUnknown`, `batchResetAllRemovesIt` (the grid's write). Debug script on a stored Flat: `resetAll true` before, Reset All leaves `{"operations":[]}` and `resetAll false` | Pass |

## Debug-script results

- DNG (RAW_00004): `decoder system wb state kelvin`; buttons under Light:
  "Light", "Reset Light", then the "As Shot" pop-up and Tone's "Auto"; no
  "Standard" pop-up, no decoder version pop-up. "Use machine learning" check box
  in Noise Reduction, off, enabled, its tooltip unchanged.
- JPEG (IMG_00001): Light starts with the same "As Shot" pop-up; no machine
  learning check box (not raw), as before.
- DNG with a stored Flat (written into the scratch catalog): `resetAll true`;
  `adjust exposure 0.5` stores `rawDecode {look: flat}` and `exposure`; `adjust
  reset all` stores `{"operations":[]}`, then `resetAll false`. History labels:
  "Debug exposure", "Reset Adjustments".

## For a person (design §12)

- M1: Light in the light and dark appearance and with Increase Contrast, on a
  system raw, an X-E3 file (LibRaw) and a JPEG: the heading starts at White
  Balance, spacing equal to today's JPEG.
- M2: a photo saved earlier as Flat opens with the decoder's default; its
  history still lists and reverts the old entries ("Profile").
- M3: Save Preset's Include grid (13 boxes, White Balance first) and a preset
  manager row whose preset had only Profile ("No settings").

## Open questions

None blocking. One requirements note for the product manager is in the
report (RI-E1: `photocli` can still set `rawDecode.decoderVersion`).

## README

- `README.md`: no mention of Profile, Look or the Decoder pop-up found.
- `CLAUDE.md` "Scope so far": the #161 entry says a LibRaw photo has "no
  Profile or Decoder choice"; with no Profile group anywhere, that clause is
  stale. The rest of "Scope so far" names no Profile control. Add this
  feature's entry (cache version 13, the two goldens deleted).
- `docs/features/_inventory.md`: for the product manager to check at Ship.
