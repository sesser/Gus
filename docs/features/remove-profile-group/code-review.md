# Remove the Profile group: code review

Owner: code-reviewer. Date: 2026-11-18. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/remove-profile-group`, 91e4e1c..d017d36 (bd3bb4d design,
ad2c070 goldens, db14992 code, 02c8672 tests, 3c18e15 cache version, d017d36
guide and status). Build and tests: `swift build` clean; `swift test` 1176
tests in 174 suites passed (this worktree, 2026-11-18).

## Verdict

Ready for QA. The change does what the PRD asks: a stored Look is read as text,
written back byte for byte, never rendered, and removed only by Reset All; the
cache version bump is justified and the deleted goldens are in a commit of their
own. No blockers and nothing to fix before QA; three nits below.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Nit | `Sources/PhotoCore/Edits/Adjustments.swift:273`, `AdjustmentPresets.swift:117-121`, `Presets/PresetFile.swift:146-149` | The legacy machine learning rule now fires when the preset's stored decode holds the legacy version, whatever its groups. Before, it fired only when Profile was among the groups. The engineer recorded this residual in `status.md` ("How it is built") and left it untested. | An older build loads a preset saved with Profile = 9.dng and groups including `profile`, and the user unticks Profile in Include. `updateAdjustmentPreset` saves `changed.adjustments.editStack`, which still holds `rawDecode {decoderVersion: 9.dng}`, with groups that no longer name `profile`. Old build: applying it never turned machine learning on, because `copying` skipped the decode. This build: `replacing` sees `source.decode.legacyMachineLearningVersion` and turns it on. That differs from R4's "works exactly as today". It is rare: the preset predates Use machine learning and was then edited in Include. A cheap fix: when the stored group list is explicit and does not name `profile`, clear `legacyMachineLearningVersion` as the catalog and preset file read it (or accept the difference by a PM ruling). | PRD R4 |
| C2 | Nit | `Sources/PhotoCore/Edits/LiveRegionRenderer.swift:115` | The doc comment of `shouldDecode(whileMoving:)` still lists "White Balance, Profile, Noise Reduction" as controls that change the decode on every frame. No control sets Profile now. | Comment only: it names a control that no longer exists. | Design §8 D4 (no stale Profile naming), dead references |
| C3 | Nit | `Tests/PhotoCoreTests/StoredLookTests.swift:104-108` | The undo and redo half of `developAndUndoKeepIt` writes the before and after stacks itself with `setEditStack`. So it checks that the catalog stores what it is given, not that the app's undo and redo keep the stored Look. The byte-for-byte round trip (`roundTripsUnchanged`) makes a failure unlikely, but AC3 names undo and redo. | No failure seen. Coverage is thinner than the AC table in `status.md` says. QA can close it with the debug script on a photo with a stored Flat: `adjust exposure 0.5; undo; redo; print adjustments` (expect `"look":"flat"` after each step). | PRD AC3 |

## Questions

- For the product manager (from C1): accept the residual legacy-preset
  difference, or have the engineer apply the fix in C1? Either is small. The
  difference only reaches a preset that an older build saved with the machine
  learning decoder in Profile and then edited in Include.
- For the main session: #218 is being built in another worktree. If it also
  bumps `PreviewCacheKey.currentPipelineVersion`, whichever branch merges second
  must go to 14 (or later). It must not keep 13, and its version tests must
  move with it. `StoredLookTests.pipelineVersion` checks `>= 13`, so it
  survives a later bump.
- RI-E1 (the engineer's): `photocli develop --set rawDecode.decoderVersion=…`
  can still store a non-machine-learning decoder version. The PRD's R4 honours
  stored ones and R8 only removes `look`, so this is consistent with the PRD as
  written. Whether the CLI should keep that power is the product manager's call.

## Checked and fine

- **R2, render.** `AdjustmentRenderer.rawDecodeSettings` no longer sets
  `boostAmount`, and nothing else reads `storedLook` (search of `Sources`). The
  one decode path is `AdjustmentRenderer.decodeSettings(for:)` →
  `Adjustments.decodeSettings`, used by previews, the live session and the 100%
  region alike. `RAWDecodeSettings.boostAmount` stays, documented as
  measurement-only (`BaselineLookMeasurementTests`). AC2: the byte-for-byte test
  `RAWDecodeTests.storedLookRendersAsDefault` (system decoder) and the LibRaw
  pipeline tests pass.
- **R5, cache version 13.** The reasoning holds. The render hash covers enabled
  operations, and a stored Look is kept, so the hash of a Flat or Neutral stack
  is unchanged (corpus hashes `raw-lookFlat` and `raw-lookNeutral` still match)
  while its pixels changed. Without the bump the old previews would be served.
  A disabled `rawDecode` was never in the hash and already rendered as default.
  Not excluding `look` from the hash is right: the stored `editStackHash` column
  would drift from the stacks without a migration (non-goal). No carry-over
  logic remains to interact with the bump (`PreviewDiskCache` only removes
  obsolete version folders).
- **R3, strict handling.** `RawDecode.init` keeps any string under `look`. A
  non-string value is dropped, as before, and no build wrote one.
  `ParameterBuilder.set(_:_: String?)` writes it back unchanged.
  `decoderVersion` and `legacyMachineLearningVersion` are as before. The
  operation's on/off flag survives `enableModules` and `setEnabled`: no group
  owns it, and its parameters are non-empty. Every write path keeps the stored
  `rawDecode`: the editor's `change`, `changeEditStacks` (batch, Auto, Rotate,
  presets), `pasted(onto:)`, history revert, and `photocli develop --set`. I
  searched for `decode =` assignments in `Sources` and found none outside
  `resettingAll` and tests. Unknown operations are untouched.
- **Reset All.** `Adjustments.resettingAll()` is the one rule. The loupe's menu
  and ⋯ item use it through `AdjustmentEditor.resetAll` (via
  `LibraryModel.resetAllAdjustments`), and the grid through `BatchActions`. It
  matches the earlier inline code, which already dropped `rawDecode`. AC12 tests
  pass. `canResetAll` and the ⋯ item read `isDefault`, which is true afterwards
  (no preserved operations).
- **Headings.** `Section.develop` is White Balance, Tone and Presence, so a
  stored Look leaves Light unmodified. `isModified(.develop)` and
  `modifiedGroups` exclude it, which is tested.
- **Presets, paste, `.guspreset`.** `Group.profile` is gone, and
  `decodeGroups` ignores the unknown `profile` name (presets with only Profile
  read as no groups, "No settings"). The catalog and preset files keep a stored
  decode (`keepingStoredDecode: true`) through rename, move, Include and export.
  New presets, Lightroom and Luminar imports never carry one. Applying one
  applies nothing from it (apart from C1's legacy case), and paste keeps the
  target's. The UI's group lists all read `presetGroups`.
- **Lightroom mapping (R7, RI-2).** `profile()` sets nothing and inserts no
  group. It matches the Standard family by whole name, trimmed and in any case,
  and reports every other name once as `.profile`. Monochrome goes only to
  `blackAndWhite` (`isGrayscale`), and a Look name wins over `CameraProfile` as
  before. Tested with both keys.
- **`photocli` (R8).** `parameterDescriptions` lists `decoderVersion` only.
  `rawDecode` appears with null group and section. `--set rawDecode.look=…` and
  `--reset rawDecode.look` fail as unknown parameters, and `--reset all` gives
  identity. `descriptionsMatchModules` still holds: `look` is written but
  deliberately not described, as the doc comment says.
- **Goldens (R9, AC5).** ad2c070 deletes only the two Look cases, PNGs and
  fingerprints, plus the corpus entries that now build those stacks explicitly.
  No other golden moved, and no tolerance changed. The
  `GPUDemosaicDecodeTests` pipeline check went from `== 12` to `>= 12`, the
  pattern earlier bumps used (`EstimateEdgeTests`, `LocalSharpenGroupOffTests`).
  It is not a loosening.
- **Machine learning (R4).** `chooseDecoder`, `offeredDecoderVersions`,
  `defaultDecoderVersion` and `decoderChoiceIsEnabled` are removed with no
  remaining caller. `machineLearningVersion(in:)` and `decoderVersions` stay
  (availability). Legacy photo stacks read as before, and the
  `MachineLearningNoiseReductionTests` changes keep their substance.
- **PhotoApp.** The Profile and Decoder pop-ups, the LibRaw note,
  `FallbackDecoderText`, `decoderItem` and `decoderDimmedHelp` are gone.
  `AdjustText.title` is exhaustive, `usesFallbackDecoder` is still used by the
  machine learning captions, and `AppKitPopUp`'s `isEnabled` and `help` are
  still used (White Balance Mode, Pixel Magnifier). The debug script's
  `adjust look`, `ml decoder` and the `decoder` and `note` fields are removed.
  The `changing` set needs no change.
- **String Catalog.** The deleted keys (Profile, Decoder, Neutral, Flat,
  `%@ (default)`, `%@ (machine learning)`, the dimmed tooltip, the LibRaw note)
  have no remaining use. "Standard" is kept for the Export sheet, with its
  comment fixed. No catalog comment names Profile. `LocalizationTests` pass.
- **Swift 6 and concurrency.** No new isolation, `Sendable` or main-actor work.
- **Rules.** No migration, no new dependency, and no persisted name with the
  product name (`look` is the existing key). Originals and sidecars are
  untouched, and the commits are signed (`%G?` = G).
- **User guide (AC10).** There is no "Profile", "Look" or "Decoder pop-up".
  Lowercase "profile" remains only in the Lightroom list and `photobench`'s
  "profiles import". Where the new sentence sits (end of the 100% section) is
  the designer's to judge.
- **Security.** No new parser, subprocess, file writing outside the library or
  network code. The one parser-adjacent change keeps a stored `look` string
  from the catalog and `.guspreset` files instead of dropping unknown ones.
  `decoderVersion` was already free text there, the value is never rendered
  or executed, and it adds no allocation path. `/security-review` is not
  needed.

## Follow-up

(After the engineer's fixes: each finding with Fixed, Not fixed (and why) or
Withdrawn, and the commit.)
