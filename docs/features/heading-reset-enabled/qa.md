Issue: #221

# Adjust headings' reset arrows enabled with nothing to reset: QA

Owner: qa-tester. Date: 2026-11-19. Step 4 of `docs/WORKFLOW.md` (bug fix: the criteria are the **Bug** section of `status.md` and issue #221).
Tested: `bug/heading-reset-enabled` at 8628df2 (cut from `develop` at d62cd4d, which is still `origin/develop`), on an Apple M4 Pro, macOS 27.2.1 (26B131), Xcode 26 SDK.

## Verdict

Passes. On a freshly opened unedited photo (JPEG and DNG, with the Black & White and Lens headings expanded) all ten heading resets are listed disabled on the branch; on a copy built from `develop` the same script lists seven enabled, and after an edit and a reset Details, Lens and Effects stay enabled. One open item for a person: how the dimmed arrows look in the glass inspector (P1). No findings.

## Acceptance criteria

The criteria are the Bug section's: expected behavior ("a heading's reset arrow is dimmed while its groups are at their defaults"), the two reproduction steps, "Reset does the same as before", and the test that fails without the fix. "Enabled" here is `NSButton.isEnabled` as `buttons` prints it, which is what AppKit draws.

| AC | How | Evidence | Result |
|---|---|---|---|
| B1. Unedited photo, Adjust tab, after 4 s: every heading reset (Crop, Spots, Light, Tone Curve, Color Mixer, Black & White, Color Grading, Details, Lens, Effects) is disabled. JPEG and DNG; Black & White and Lens headings expanded | Script | S1 (A1, A1x). `develop`: Light, Tone Curve, Color Mixer, Color Grading, Details, Lens, Effects enabled, both files. Branch: all ten disabled, both files, B&W collapsed and expanded | Pass |
| B2. Bug step 2: after an edit and a reset, nothing stays enabled at 1 s and 4 s (the "lag") | Script | S2 (loop, stage S2 and S3). `develop`: Details, Lens, Effects stay enabled at +1 s and +4 s (JPEG; DNG after Tone Curve, Color Mixer, Black & White, Color Grading, Spots, Crop too). Branch: all disabled at 0.3 s, 1 s and 4 s, 10 headings x 2 files | Pass |
| B3. An edit under a heading enables only that heading's reset (all ten headings, JPEG and DNG) | Script | S2 stage S0: exactly one `E`, the edited heading's, in all 20 runs on the branch. On `develop` the same runs also list Details, Lens and Effects (and sometimes Light, Tone Curve, Color Mixer, Color Grading) enabled | Pass |
| B4. Reset dims it again at once and at 4 s | Script | S2 stages S1 (0.3 s after the reset), S2 (+1 s), S3 (+4 s): all disabled, 20 runs. A reading taken in the same script step as the reset still shows enabled (SwiftUI had no run-loop turn yet); by 0.3 s it is dimmed | Pass |
| B5. A group turned off with values kept still offers its reset; the reset brings the photo back to the identity stack | Script | S3 (T1: exposure 0.5 then `adjust off light`; T2: sharpening amount 40 then `adjust off sharpening`). Stack holds the operation with `"isEnabled":false`, hash is the identity hash, Reset Light / Reset Details enabled at 1 s and 4 s; reset gives stack `[]`, all disabled | Pass |
| B6. Reset itself does what it did | Script | S4. Real mouse path (`click` on the Reset Light button after `scroll 400`): `hits Button < AppKitPlatformViewHost<…AppKitButton>`, stack goes from the exposure operation to `[]`, all dimmed; identical on `develop` (stack `[]`, though Details/Lens/Effects remain enabled there). `adjust reset <section>` (`editor.reset`) in S2 for every heading gives identity hash `6c76a50e5dc3` | Pass |
| B7. A click on a dimmed arrow changes nothing | Script | S4: `click` on Reset Light on the unedited photo does not hit the button (hits the scroll view's content), stack stays `[]` | Pass |
| B8. Switching photos re-evaluates | Script | S5: Light edited on IMG_00001 (Light enabled), focus IMG_00002 (all disabled), RAW_00003 (all disabled), back to IMG_00001 (Light enabled, others disabled), reset (all disabled). On `develop` the same script leaves seven enabled on the unedited photos | Pass |
| B9. The test that fails without the fix | Test | `HeadingResetTests` "Every heading's reset is dimmed through SwiftUI's environment too" (`headingResetsCarryDisabled`). Mutation check in a scratch copy outside the checkout: with `.disabled(!canReset)` removed from `AdjustSection`, the test fails ("the reset at Sources/PhotoApp/Views/AdjustControls.swift:510 has isEnabled: canReset but its modifiers carry [], not .disabled(!canReset)"); with the line restored it passes (7 of 7). The other six tests in the suite pass with the line removed, as expected: they pin the model rule (`isModified`), which was never wrong | Pass |
| B10. The model rule the fix leans on (what "at defaults" means) | Test | `HeadingResetTests`: `uneditedPhoto`, `editAndReset`, `operationsOutsideTheHeadings`, `turnedOffGroup`, `legacyMachineLearningDecoder`, `scannerReadsTheModifierChain`. Read each: they fail if `isModified` disagreed with the rule in `status.md` (every section, exhaustive switch over `Group` in `edited(_:)`) | Pass |
| B11. No regressions elsewhere | Test | Full `swift test`: 1247 tests in 177 suites passed (78.5 s), `DeferredRenderTests` (#229) did not flake. Log kept in the QA scratch folder (see S0) | Pass |
| B12. How the dimmed arrows are drawn in the glass inspector | Person | P1 (`snapshot` leaves the glass panes blank) | Open |

Limit of the evidence: PhotoApp has no test target, so the real button's state is checked by the debug script, not by a test; the test guards the source shape (the modifier on the button's own chain) and the model rule. The general fix, `AppKitButton` carrying its own enabled state into the environment, is #76.

## Findings

None.

Observations (not findings):
- On `develop` the bug is order-dependent, as the root cause says: a click that expands the Black & White heading (a structural update) made all seven resets list disabled on that launch, and the first loop run on the DNG (Light) also showed none enabled; other runs showed them stuck. On the branch no run, in any order, listed a heading reset enabled without an edit.
- `Reset Channel` (the tone curve's channel reset) is not a heading reset and was already disabled; it is not in these tables.
- `spot add` does nothing until `spots on` (Edit Spots); the Spots rows use it. Not related to this fix.

## Scripts

Setup (all in the QA scratch folder `/private/tmp/claude-501/-Users-randy-Projects-Gus/e0e0f80d-a682-4069-aabb-35e62561cf82/scratchpad/qa221`, called `$S` below):

```
git archive origin/develop | tar -x -C $S/develop-src          # develop at d62cd4d
Scripts/build-app.sh                                            # branch bundle, in the checkout's build/
(cd $S/develop-src && Scripts/build-app.sh)                     # develop bundle
cp -R <each build/Gus.app> $S/copies/{branch,develop}/
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest{branch,develop} <copy>/Contents/Info.plist
codesign --force --deep --sign - <copy>
swift run -c release photobench generate --output $S/photos --jpeg 2 --dng 2 --jpeg-size 640x480 --dng-size 640x480
swift run -c release photobench import --library-root $S/lib --source $S/photos
```

The scratch library holds IMG_00001.JPG, IMG_00002.JPG, RAW_00003.DNG, RAW_00004.DNG and 100 HEICs. Every launch is `<copy>/Contents/MacOS/Gus --library-root $S/lib --debug-script "<script>"` (`$S/run.sh <branch|develop> <name> "<script>"` keeps the `debug-script:` lines in `$S/logs/<which>-<name>.log`). `$S/summ.py` reduces each `buttons` dump to one letter per heading reset (E enabled, d disabled).

Every script starts with the prefix `P` = `wait 2; focus <photo>; loupe; inspector on; tab adjust; wait 4;` and ends with `quit`.

**S0. Full test.** `swift test` in the checkout at 8628df2: `Test run with 1247 tests in 177 suites passed after 78.485 seconds.` Exit 0, no `DeferredRenderTests` failure. Log: `$S/swift-test-full.log`.

**S1. Unedited photo (B1).**
```
P buttons; quit
```
with `<photo>` IMG_00001 and RAW_00003, on both bundles; and again with the Black & White heading expanded by `scroll 1300; click 1040 248; wait 1.5; scroll 0` (the expansion is a preference of the copy, so later runs start with it; the Lens heading is expanded by default). Result (`$S/logs/*-a1-*.log`):

| | Crop | Spots | Light | Tone Curve | Color Mixer | B&W | Color Grading | Details | Lens | Effects |
|---|---|---|---|---|---|---|---|---|---|---|
| `develop`, JPEG | d | d | E | E | E | d | E | E | E | E |
| `develop`, DNG | d | d | E | E | E | d | E | E | E | E |
| `develop`, B&W and Lens expanded | d | d | E | E | E | d | E | E | E | E |
| branch, JPEG | d | d | d | d | d | d | d | d | d | d |
| branch, DNG | d | d | d | d | d | d | d | d | d | d |
| branch, B&W and Lens expanded, JPEG and DNG | d | d | d | d | d | d | d | d | d | d |

**S2. One edit per heading, then its reset (B2, B3, B4).** `$S/heading-loop.sh <branch|develop> <photo>`: for each heading one launch of
```
P <edit>; wait 1; print adjustments; buttons; <reset>; wait 0.3; buttons; wait 1; buttons; wait 3; buttons; print adjustments; quit
```
reading S0 (edited, 1 s), S1 (reset + 0.3 s), S2 (+1 s), S3 (+4 s):

| Heading | `<edit>` | `<reset>` |
|---|---|---|
| Light | `adjust exposure 0.5` | `adjust reset develop` |
| Tone Curve | `adjust curve rgb 0,0 0.5,0.6 1,1` | `adjust reset tone` |
| Color Mixer | `adjust mix red 10 0 0` | `adjust reset colorMixer` |
| Black & White | `adjust bw on` | `adjust reset blackAndWhite` |
| Color Grading | `adjust grade shadows 200 0.5` | `adjust reset colorGrading` |
| Details | `adjust amount 40` | `adjust reset details` |
| Lens | `adjust align redcyan 5` | `adjust reset lens` |
| Effects | `adjust grain 30` | `adjust reset effects` |
| Spots | `spots on; wait 1; spot add 0.5 0.5` | `spot clear` |
| Crop | `adjust crop turn left` | `adjust crop reset` |

Branch, JPEG (clean run, `$S/logs/summary-branch-jpg-clean.txt`) and DNG (`summary-branch-dng.txt`): S0 has exactly the edited heading enabled in all 20 runs; S1, S2 and S3 have all ten disabled in all 20. (A first JPEG pass was discarded: an earlier probe had left a spot on IMG_00001, so Spots read enabled throughout; the pass was repeated on the cleared photo.)

`develop`, JPEG and DNG (`summary-develop-jpg.txt`, `summary-develop-dng.txt`): S0 also lists Details, Lens and Effects enabled in 19 of 20 runs (and Light, Tone Curve, Color Mixer, Color Grading in some). After the reset, Details, Lens and Effects stay enabled at S1, S2 and S3 whenever they were not the heading just reset: e.g. JPEG Light: `S3 Light d, Details E, Lens E, Effects E`; Details run: `S3 Details d, Lens E, Effects E`. One run (DNG, Light) listed everything disabled.

**S3. Turned off, values kept (B5).**
```
P adjust exposure 0.5; adjust off light; wait 1; print adjustments; buttons; wait 3; buttons; adjust reset develop; wait 1; buttons; print adjustments; quit
P adjust amount 40; adjust off sharpening; wait 1; print adjustments; buttons; wait 3; buttons; adjust reset details; wait 1; buttons; print adjustments; quit
```
Both: stack holds the operation with `"isEnabled":false`, hash `6c76a50e5dc3`; the heading's reset is enabled at 1 s and at 4 s, only that heading's; after the reset the stack is `{"operations":[],"schemaVersion":1}` and all are disabled.

**S4. Real click (B6, B7).** After `scroll 400` the Reset Light button is at `1281,379` (`buttons` reports the position).
```
P scroll 400; wait 1; buttons; click 1281 379; wait 1; print adjustments; adjust exposure 0.5; wait 1; print adjustments; buttons; click 1281 379; wait 1; print adjustments; buttons; wait 3; buttons; quit
```
Branch: the first click (arrow dimmed) hits the scroll view's content, stack `[]`; after the edit Light is the only one enabled; the second click hits `Button < AppKitPlatformViewHost<…AppKitButton>`, stack `[]`, all disabled at once and at 4 s. `develop`: first click hits the button (it was enabled), stack `[]`; after the edit seven are enabled; after the click Details, Lens, Effects stay enabled at 1 s and 4 s.

**S5. Switching photos (B8).**
```
P adjust exposure 0.5; wait 1; buttons; focus IMG_00002; wait 2; print title; buttons; focus RAW_00003; wait 2; print title; buttons; focus IMG_00001; wait 2; print title; buttons; adjust reset develop; wait 1; buttons; print adjustments; quit
```
Branch: Light only (IMG_00001, edited) / none (IMG_00002) / none (RAW_00003) / Light only (IMG_00001) / none (after reset), stack `[]`. `develop`: Light and seven others enabled on the unedited photos.

**S6. Mutation check (B9).** `git archive HEAD` into `$S/mutation-src`, the line `.disabled(!canReset)` deleted from `Sources/PhotoApp/Views/AdjustControls.swift`, then `swift test --filter HeadingResetTests`: 7 tests, 1 issue, `Every heading's reset is dimmed through SwiftUI's environment too` failed as quoted above, exit 1. The file restored from the checkout, same command: 7 of 7 passed. Nothing in the checkout was edited.

**Owner's data.** Before and after the runs a read-only listing of every file under `~/Library/Application Support/Gus` and `~/Library/Caches/Gus` (418 files; name, size, modification time) was identical, no file is newer than the start of the run, and `pgrep -x Gus` finds no instance. Every launch carried `--library-root`.

## For a person

- **P1. The dimmed arrows' look (B12; the designer's check in `status.md` "For a person", no `review.md` for this fix, so no M-number).** Run the bundle on a scratch library: `Scripts/build-app.sh`, then `build/Gus.app/Contents/MacOS/Gus --library-root <scratch library from photobench>`; open an unedited photo in the loupe, Adjust tab. Look at the reset arrow at the right of Light, Tone Curve, Color Mixer, Color Grading, Details, Lens and Effects: each should be drawn dimmed, like Crop & Straighten, Spots and Black & White, and not at full strength. Change one slider under one heading: only that heading's arrow undims. Press it: it dims again. Repeat in light, dark and with Increase Contrast on; look for an arrow too faint to see as a button once enabled, or one still at full strength with nothing to reset. VoiceOver, macOS 15 and macOS 26 are not part of this check.

## Follow-up

(Reruns after fixes, and the owner's sign-off, are recorded here.)
