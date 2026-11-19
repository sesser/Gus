# Remove the Profile group: QA

Owner: qa-tester. Date: 2026-11-18. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/remove-profile-group` at 916d262, on an Apple silicon Mac,
macOS 27.2.1 (26B131), Xcode SDK 27.2. Issue #219 (PRD revised 2026-11-18, 12
acceptance criteria).

## Verdict

Passes. All 12 acceptance criteria pass by test or by script (the full
`swift test`: 1177 tests in 174 suites, none failed; the scripted runs on a copy
of the bundle with a scratch library). Mutation checks show the key tests fail
without the behavior. Nothing needs the engineer. What only a person can check
(the look of the new Light heading, an X-E3 file, the Include grid, a few
menu and undo details) is in P1 to P7, all from the designer's M1 to M7.

Safety: every launch passed `--library-root` (a `photobench` scratch library).
Run on a copy of the bundle with the identifier `me.sesser.gus.debugtest219qa`
(and `…qadev` for the `develop` bundle). After the runs: no Gus process is
running, nothing under `~/Library/Application Support/Gus` or
`~/Library/Caches` is newer than when I started, and `me.sesser.gus.plist` is
untouched (only my two debug-test preference files are new).

## Acceptance criteria

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 (no Profile heading, pop-up or note) | Script; Person | Script A: on a system-decoded DNG and on a JPEG, Light's controls are `Reset Light`, the `As Shot` White Balance Mode pop-up, `Auto`; no Standard/Look/Decoder pop-up, no note; `Use machine learning` is the first Noise Reduction control on the DNG, absent on the JPEG. Same listing on `develop` shows the `Standard` pop-up (script D-dev), so the check can tell. A LibRaw photo: the scratch library has none (the synthetic DNGs are system-decoded), the branch that showed the note is deleted (`status.md`), so by eye | Pass (script); LibRaw look open (P1) |
| AC2 (stored `look` renders as without) | Test; Script | `RAWDecodeTests.storedLookRendersAsDefault` (flat, neutral; byte for byte, system decoder); `LibRawDecoderTests` (flat as plain); `AdjustmentsModelTests` (boost never set). Script I: `photocli render` of a stored Flat and of the same photo with an empty stack give the same SHA-256 (`f6b0fab5…`); on `develop` they differ (`ff7feda7…` vs `f6b0fab5…`) | Pass |
| AC3 (stored `look` kept by edit, undo, redo, paste, batch, `photocli develop`) | Test; Script | `StoredLookTests`: `valueWritesKeepIt`, `roundTripsUnchanged`, `batchKeepsIt`, `developKeepsIt`, `editorUndoAndRedoKeepIt`; `EditStackCorpusTests`. Script B: with the window's real undo manager, `adjust exposure 0.5; undo; redo; undo` on a stored Flat keeps `"look":"flat"` after every step (hash `597736ba…` when only the look is stored, `6a72b130…` with exposure) | Pass |
| AC4 (ML and a stored non-ML `decoderVersion` as before) | Test | `MachineLearningNoiseReductionTests` (suite passes), `StoredLookTests.storedDecoderVersionRenders`. Script A: the Use machine learning check box, tooltip and state as before | Pass |
| AC5 (goldens unchanged; version 13 iff renders changed) | Test | Full run: every `Goldens` test passes, no skips (the skips are the env-gated opt-in suites), no update run; `StoredLookTests.pipelineVersion` (version 13, a stored Look keeps its hash, changed its render); `status.md` states the reasoning (R5) | Pass |
| AC6 (old preset with `rawDecode` imports, applies nothing, lists no Profile) | Test; Script | `StoredLookTests.oldPresetsInTheCatalog`, `oldPresetFiles`, `noProfileGroup`; Script H: presets stored with `rawDecode {look: neutral}` and groups `profile` and `light,profile` apply with no error; the first changes nothing and adds no History entry, the second applies only its exposure and no `rawDecode` | Pass |
| AC7 (Lightroom Flat/Neutral reported; Standard family not) | Test; Script | `StoredLookTests` AC7 tests (Flat, Neutral, Camera Neutral, Camera Standard, Adobe Landscape, Vivid, Vintage reported; Standard, Adobe Color, Adobe Standard, default, Embedded, any case, not; monochrome as Black and white only), `PresetTests.convertsTemplates`. Script J: `.xmp` with Flat -> "Profiles and creative looks (1)"; with Adobe Color -> no line; Flat plus Adobe Monochrome -> "Black and white (approximated) (1)" only; none of the saved presets holds `rawDecode` | Pass |
| AC8 (`photocli`: no `look`; `--set look=flat` fails) | Test; Script | `CommandTests.setParsing`, `adjustmentsListsEveryModule`. Script I: `photocli adjustments` has no `"look"` (`develop`: 1); `render --set look=flat` and `--set rawDecode.look=flat` exit 1 with `invalidEdit` ("rawDecode has no parameter look") | Pass |
| AC9 (Look goldens deleted in their own commit) | Test; Script | `git show --stat ad2c070`: deletes only `raw-lookFlat` and `raw-lookNeutral` (PNG and fingerprint each) plus the two cases that built them and a corpus line; `Goldens/` has no `look` file but the three `lookTable-*` | Pass |
| AC10 (user guide) | Script | Case-sensitive search of `docs/USER_GUIDE.md` for Profile, Look, Decoder pop-up: none. Lowercase hits are the Lightroom list ("profiles and creative looks", "A standard profile"), "baseline look" (the LibRaw color step) and `photobench`'s "profiles import" | Pass |
| AC11 (history entry with `look` reverted to, then undone) | Test | `StoredLookTests.historyRevertAndUndo` | Pass |
| AC12 (Reset All clears the stored decode; not left enabled) | Test; Script | `StoredLookTests.resetAllRemovesIt` (a Look, a Look with a decoder version, a decoder version alone), `resetAllKeepsUnknown`, `batchResetAllRemovesIt`. Script C: stored Flat, `resetAll true`; `adjust reset all` leaves `{"operations":[],…}` (hash `6c76a50e…`, the empty stack's) and `resetAll false` | Pass |

Counts: 12 of 12 pass. By test alone: AC4, AC5, AC9, AC11. By test and script: AC2, AC3, AC6, AC7, AC8, AC12. By script (plus a look): AC1, AC10 (search). Open for a person: the look half of AC1 (P1). Failed: 0.

### Do the tests fail without the behavior?

The engineer's new tests do not compile on `develop` (the API changed), so I
mutated a scratch copy of the branch (`git archive` of HEAD, outside the
checkout) and ran three tests there:

- `boostAmount = 0` set again for a stored flat or neutral look:
  `RAWDecodeTests.storedLookRendersAsDefault` fails for both (`stored == without`).
- `resettingAll()` made to keep the decode: `StoredLookTests.resetAllRemovesIt`
  (3 cases) and `batchResetAllRemovesIt` fail.

Both mutations are caught. The scratch tree is not in the checkout.

## Findings

None for the engineer. Two observations, nothing filed:

- **Reset arrows read enabled on an unedited photo (the engineer's note):
  real, and pre-existing on `develop`.** In `buttons`, on a freshly opened
  unedited photo every heading's reset (`Reset Light`, Tone Curve, Color Mixer,
  Color Grading, Details, Lens, Effects) lists as enabled, still so after 9 s
  (script G). Identical on the `develop` bundle (script G-dev). `buttons` reads
  `NSButton.isEnabled`, so this is the state the button is given, not only a
  listing quirk, but I could not see whether it is drawn dimmed (the glass
  inspector is blank in snapshots). After the first edit and a reset they
  update: Light, Tone Curve, Color Mixer and Color Grading list disabled; Details,
  Lens and Effects stay enabled even then, on both builds. Not caused by this
  branch. On this branch the reset after an exposure edit on a stored-Flat
  photo is disabled again (script F, with a 3 s wait; at 1 s the listing still
  showed it enabled: the update lags the stack).
- **Operation ids change when a stack is read and written back.** The seeded
  stored stack had id `00000000-0000-4000-8000-000000000000`; after any edit the
  `rawDecode` operation has a new id each time (`print adjustments`). The
  `look` value and the render hash (`597736ba…`) are unchanged. This is how
  `Adjustments` already worked (ids are not part of the hash); R3 is met in value.

Design questions: none. Requirements issues: none.

## Scripts

All run on `$S/app/Gus.app` (a copy of `build/Gus.app`, identifier
`me.sesser.gus.debugtest219qa`, re-signed ad hoc) with
`--library-root $S/lib`, `$S` being the scratchpad. The library came from
`swift run -c release photobench generate --output $S/src --jpeg 2 --dng 3 --heic 2 --dng-without-color 1`
and `photobench import --library-root $S/lib --source $S/src`. Seeding a stored
Flat (the app can no longer write one), with the app not running:

```
STACK='{"operations":[{"id":"00000000-0000-4000-8000-000000000000","isEnabled":true,"kind":"rawDecode","kindVersion":1,"parameters":{"look":"flat"}}],"schemaVersion":1}'
HASH=597736ba24fc7eda744f36d359feef796607c3353ed1cfe9346acd101dd8f6bd
sqlite3 $S/lib/Library/catalog.sqlite "update version set editStack='$STACK', editStackHash='$HASH' where id in (6,7)"
```

Versions 6 and 7 (`RAW_00004`, `RAW_00005`) hold the stored Flat; `RAW_00003`
and the JPEGs are unedited. Each script is run as
`$S/app/Gus.app/Contents/MacOS/Gus --library-root $S/lib --debug-script "<script>"`.
`inspector on` is needed: the inspector starts hidden in a scripted launch.

**A: AC1, the Adjust tab of a system raw and a JPEG.**
`wait 2; focus RAW_00003; loupe; inspector on; tab adjust; ml ready; wait 2; print ml; print adjustments; buttons; focus IMG_00001; ml ready; wait 1; print adjustments; buttons; quit`
Showed: DNG: `decoder system`, Light's controls `Reset Light`, `As Shot` pop-up (modes As Shot, Auto, Daylight, Cloudy, Shade, Tungsten, Fluorescent, Flash, Custom), `Auto`; no other pop-up between Light and Tone Curve; `Use machine learning` off, enabled, with its tooltip. JPEG: same Light controls, no machine learning box.

**B: undo and redo of a stored Look (the C3 check).**
`wait 2; focus RAW_00004; loupe; inspector on; tab adjust; ml ready; wait 1; print adjustments; adjust exposure 0.5; wait 1; print adjustments; undo; wait 1; print adjustments; redo; wait 1; print adjustments; undo; wait 1; print adjustments; history wait; history; quit`
Showed: five stacks in turn: look only (hash `597736ba24fc`), look + `ev 0.5` (`6a72b130b5c1`), look only, look + `ev 0.5`, look only. `"look":"flat"` present every time. History rows, newest first: Undo Debug exposure, Redo Debug exposure, Undo Debug exposure, Debug exposure.

**C: Reset All (AC12).**
`wait 2; focus RAW_00005; loupe; inspector on; tab adjust; ml ready; wait 1; print menustate; focus RAW_00004; ml ready; wait 1; print adjustments; print menustate; buttons; adjust reset all; wait 1; print adjustments; print menustate; history wait; history; quit`
Showed: on stored Flat `resetAll true`; after `adjust reset all` the stack is `{"operations":[],"schemaVersion":1}`, hash `6c76a50e5dc3` and `resetAll false`; History's newest row "Reset Adjustments".

**D and D-dev: reset arrows, on the branch and on `develop`.**
`wait 2; focus RAW_00003; loupe; inspector on; tab adjust; ml ready; wait 2; print adjustments; buttons; adjust exposure 0.5; wait 1; print adjustments; buttons; adjust reset develop; wait 1; print adjustments; buttons; quit`
(`develop`: `ml ready` replaced by `wait 1`; bundle `$S/appdev/Gus.app`, identifier `…debugtest219qadev`, built from `git archive` of 91e4e1c in `$S/dev`, library `$S/libdev`.)
Showed: the pattern in Findings, identical on both; `develop` also lists the `Standard` pop-up under Light, the branch does not. After `adjust reset develop` on both, `Reset Light` is disabled.

**E and F: Light's reset on a stored-Flat photo (P5).**
`wait 2; focus RAW_00005; loupe; inspector on; tab adjust; ml ready; wait 2; adjust exposure 0.5; wait 1; adjust reset develop; wait 3; print adjustments; buttons; wait 2; buttons; quit`
Showed: stack back to the stored Flat alone, `Reset Light`, `Reset Tone Curve`, `Reset Color Mixer` disabled; `menustate` `resetAll true` throughout (the Look is not a Light edit, so the heading is unmodified, but Reset All is on).

**G and G-dev: first-open listing.** `wait 2; focus RAW_00003; loupe; inspector on; tab adjust; wait 6; buttons; wait 3; buttons; quit` on both bundles: 7 resets listed enabled, 4 `Reset Channel`/`Reset Crop`/`Delete All Spots` disabled lines, identical output.

**H: old presets.** Two rows inserted into `adjustmentPreset` (groups `profile` with `rawDecode {look: neutral}`; groups `light,profile` with that and `exposure ev 0.7`), then
`wait 2; focus RAW_00003; loupe; inspector on; tab adjust; ml ready; wait 1; print adjustments; preset apply OldProfileOnly; wait 1; print adjustments; history wait; history; preset apply OldLightProfile; wait 1; print adjustments; history wait; history; quit`
Showed: first apply leaves the empty stack and adds no History entry; second leaves `exposure ev 0.7` and no `rawDecode`; History gets one "Apply Preset OldLightProfile".

**I: photocli (branch `.build/debug/photocli`, `develop` `$S/dev/.build/release/photocli`, copies of the scratch library).**
`photocli adjustments | grep -c '"look"'` (branch 0, develop 1);
`photocli render --version 6 --library-root $S/lib2 --out o.png --set look=flat` and `--set rawDecode.look=flat` (exit 1, `invalidEdit`; develop: exit 0);
`photocli render --version 7 --library-root $S/lib2 --out flat.png --long-edge 1200` against the same with `--stack empty.json` (SHA-256 equal on the branch, different on `develop`).

**J: Lightroom import (AC7, P7).** Three `.xmp` presets with `crs:CameraProfile="Flat"`, `"Adobe Color"` and Flat plus a `crs:Look` of Adobe Monochrome; `wait 2; preset import $S/xmp/<name>.xmp; quit` each. Showed the three summaries in the AC7 row.

## For a person

Build and run on a scratch library, never your own: `Scripts/build-app.sh`, copy the bundle, set its own identifier (`plutil -replace CFBundleIdentifier -string me.sesser.gus.check build-copy/Gus.app/Contents/Info.plist`, then `codesign --force --deep --sign - …`), then
`<copy>/Contents/MacOS/Gus --library-root <scratch library from photobench>`. A stored Flat Look cannot be made in the app; the seeding command under Scripts does it on a scratch catalog. No VoiceOver, macOS 15 or macOS 26 checks.

- **P1 (M1, D1; the look half of AC1).** Adjust tab on a system-decoded raw, on an X-E3 file (LibRaw) and on a JPEG, in the light and dark appearance and with Increase Contrast: Light's first row after the heading is White Balance, with the same space under the heading a JPEG had; no Profile row, no note, no gap. Resize the inspector narrow and wide: nothing clips. (Scripted: the controls are present in the right order; only the look is open.)
- **P2 (M2, R2, R11).** A photo saved earlier as Flat or Neutral (seed one) opens with the decoder's default contrast and no sign of it in the tab. Its History panel still lists the old entries; choosing one adds an entry and does not change the picture. (Scripted: the stored value survives edits, undo and redo and the pixels match the no-look render.)
- **P3 (M3, D5).** File ▸ Save Preset: the Include grid has 13 boxes, White Balance first, the last row one box and an empty cell, aligned. In the preset manager a preset that held only Profile reads "No settings"; an old "All settings" preset still reads "All settings". (Scripted: groups read as `light` etc.; the grid's look is not.)
- **P4 (M4).** Apply the "No settings" preset to a photo with the real menu: nothing changes, no empty Undo step (the script showed no History entry; Edit ▸ Undo's title and state are not checked). An extra Undo step is a finding.
- **P5 (M5, RI-1).** On a photo whose only stored edit is a Flat Look: Light has no check box and a dimmed reset arrow after the heading is first edited and reset (see the observation: the first-open arrow lists enabled on `develop` as well, so judge the arrow after one edit and reset); Reset All Adjustments (menu and ⋯) is enabled, clears it, and is dimmed afterwards. (Scripted: `resetAll` true then false, the stack empty after it, the Look surviving an edit.)
- **P6 (M6, D3).** System raw: Use machine learning is the first row of Noise Reduction, tooltip and caption as before. X-E3 file: the check box is dimmed with "Not available for this camera.", Luminance only, no Color row, no note anywhere in Light. (Scripted for the system raw only.)
- **P7 (M7, D6).** In the real preset manager, import one Lightroom preset with a Flat profile, one with Adobe Color or Standard and one with a Flat profile and a Monochrome look: the summary reads as in script J and the page looks right (wording, layout). (Scripted: the summary text for all three; the sheet's look is not.)

## Follow-up

No findings to rerun.

**Owner's sign-off, 2026-11-19.** The owner checked by eye on a `photobench`
scratch library and signed off: "I also checked #219 and it's fine too".
Commit signed off: `4ebbc1d` (branch head when recorded). It carries `916d262`
(code review second pass) and the content of `f4b64b1` (review fixes), with
this QA file; no source changed after `f4b64b1`.

| P item | State |
| --- | --- |
| P1 (look half of AC1) | Checked by the owner, fine |
| P2 (stored Flat or Neutral photo opens with the decoder's default; History) | Open: needs a photo with a stored Flat Look, seeded with the Scripts command; none was prepared, and the owner did not report it |
| P3 (Include grid, "No settings") | Checked by the owner, fine |
| P4 (No settings preset, no empty Undo step) | Checked by the owner, fine |
| P5 (stored Flat Look: Light check box, reset arrow, Reset All Adjustments) | Open: same reason as P2; the owner did not report it |
| P6 (Use machine learning, X-E3 caption) | Checked by the owner, fine |
| P7 (Lightroom import summaries) | Checked by the owner, fine |

The owner named no checks left open. P2 and P5 are listed open here because
they need a seeded photo that was not prepared, unless the owner says they were
done. Scripted checks stand for both (the stored value survives edits, undo and
redo; `resetAll` true then false). No VoiceOver, macOS 15 or macOS 26 checks.
The open checks go to the standing manual-checks issue (#82).
