Issue: #218

# Black & White module (film filters): status

Owner: swift-macos-engineer. Branch `feature/bw-module`. Spec: the PRD (issue
#218, revised 2026-11-18) and [design.md](design.md).

**State: Done** (2026-11-18). Everything is built and every acceptance
criterion has a passing test or a scripted check. The owner ruled on every open
question on 2026-11-18 (see Rulings), and the PRD (R3, R7, R10, AC7) and
design.md (§2, §3.1, §6, §15, §19, §21) were amended to match. Rereading both
after the rulings found two things to bring in line, both done: the AC7 test now
also checks that Saturation and Vibrance leave the gray values unchanged, and the
user guide now says that a mask's Saturation and Vibrance do nothing on a gray
photo and that a per-channel Tone Curve acts like one more filter. Next: code
review and the designer's review, then QA.

## Build and test

| When | `swift build` | `swift test` |
|---|---|---|
| Baseline (develop at d2d0db2, before any change) | Pass, no warnings | Not run on its own. The first full run with this branch's model in place failed only on two of this branch's own checks (an existing test that walks every heading, and missing catalog strings), both fixed |
| Latest (2026-11-18, after the review fixes) | Pass, no new warnings (two existing warnings in `SmartAlbumTests.swift` and `VirtualCopiesTests.swift` remain) | 1189 tests in 174 suites pass (`BlackAndWhiteTests`: 27). Two earlier full runs each failed once in `DeferredRenderTests` ("Core Animation renders an unread deferred image…", at a different assertion each time). That suite passes alone three times out of three, and the third full run passed. This branch touches none of its code, so the failure is a load-dependent flake |
| Bundle | `Scripts/build-app.sh` passes; `vtool` shows sdk 27.2, minos 15.0 | |

`PreviewCacheKey.currentPipelineVersion` is still 12. No migration. No existing
golden moved: `GoldenTests` failed only on the three new cases until they were
recorded with `UPDATE_GOLDENS=1` in their own commit. That run also rewrote the
eight RAW golden fingerprints, because this Mac is now on macOS 27.2.1 (26B131)
and they were made on 27.2 (26B123). Those rewrites were reverted, not
committed; the main session has the follow-up proposed in the engineer's report.

## What was built

- **PhotoCore** `Edits/BlackAndWhite.swift`: the `BlackAndWhite` module (kind
  `blackAndWhite`; parameters `on`, a boolean, and `yellow`, `orange`, `red`,
  `green`, `blue`, 0 to 100, defaults left out). Its group and heading are
  `Adjustments.Group.blackAndWhite` and `Section.blackAndWhite`, placed after
  Color Mixer and before Color Grading. The step is
  `AdjustmentRenderer.blackAndWhite`, a `CIColorMatrix` in the working space.
  `Adjustments.setEnabled(.blackAndWhite, true)` switches `on` on, and
  `enableModules(changedFrom:)` switches it on when a filter changes.
  `photocli develop`'s `EditStack.applying` lets an explicit `on` win. There is a
  parameter description (`AdjustmentParameterTests` covers it).
  `Edits/SourceColorModel.swift` reads whether a file is gray from its header.
- **PhotoApp**: `Views/BlackAndWhiteSection.swift` (the heading),
  `Views/BlackAndWhiteText.swift` (its words), `Model/BlackAndWhiteActions.swift`
  (the editor's changes), the Adjust ▸ Black & White ▸ submenu
  (`LibraryCommands`, `LibraryMenuContext`), an optional track tint on
  `AdjustSlider`/`SliderRow`, `AdjustmentEditor.sourceIsMonochrome`,
  `Model/DebugBlackAndWhiteCommands.swift`, and `buttons` in the debug script
  now prints segment selections and check box states.
- **Tests** `BlackAndWhiteTests.swift`, `Reference/BlackAndWhiteReference.swift`,
  three goldens (`blackAndWhite-noFilter-patchChart`,
  `blackAndWhite-red-hazyLandscape`, `blackAndWhite-yellowGreen-hueRamp`), and
  B&W added to `resettingEverySectionGivesBackTheIdentity`.
- **Docs**: `docs/USER_GUIDE.md` (a Black & White paragraph after the raw
  paragraphs, and the "All settings" preset note).

## Engineering answers to the PRD's open questions

**Render position.** The conversion runs in `globalSteps` right after the
Color Mixer and before Vibrance, Saturation and Color Grading. In the renderer
that means after White Balance, Exposure, Highlights and Shadows, Dehaze,
Clarity and the tone table (Contrast, Whites, Blacks, the Tone Curve). The masks,
the look-up table, Vignette, noise reduction, sharpening and Grain all come
after it. It cannot come both after the Color Mixer and before the Tone Curve,
as R7 says, without moving the Color Mixer ahead of the tone table, and that
would change every existing photo with both a mixer and a tone edit (R13). The
alternatives are in RI-1.

**Group order.** `Group` has `… colorMixer, blackAndWhite, colorGrade …` and
`Section` has `… colorMixer, blackAndWhite, colorGrading …`, so Save Preset and
Manage Presets list it in the tab's order.

**Grain stays neutral.** Grain with its Color at 0 adds the same amount to R, G
and B, and Vignette is a gain. Both come after the conversion, so the result
stays exactly gray. `grainStaysGray` checks for exact equality.

**Luminance weights.** The weights are Rec. 709's (0.2126, 0.7152, 0.0722),
applied to working-space values (linear Rec. 2020), as R3 says. The rest of the
renderer computes luminance with Rec. 2020's weights (0.2627, 0.6780, 0.0593):
masks' luminance range, grain's tonal weights, local tone. This is not a
blocker, and the PRD is explicit, but the product manager may want to confirm
it (RI-2).

**Filter transmittance.** These are my estimates, not confirmed by the owner.
Each is a filter's share of each working-space channel at full strength. I
estimated them from the published pass bands of the classic filters: yellow is
a long-pass from about 465 nm, orange from about 530 to 560 nm, and red from
about 580 to 600 nm; green passes a band of about 490 to 580 nm with its peak
near 530 nm, and blue a band of about 415 to 480 nm with its peak near 440 nm.
I set each channel's value by eye over that channel's approximate band. Sources
read 2026-11-18: [Wratten number](https://www.Wikipedia.com/wiki/Wratten_number),
[Comaro gelatin filters](https://www.comaroptics.com/components/filters/gelatin-and-polyester-colour-filters),
[Knight Optical Wratten band-pass](https://www.knightoptical.com/stock/default/filters/wratten-filter/wratten-colour-filter-bandpass.html).
These sources disagree by tens of nanometers.

| Filter | Red | Green | Blue |
|---|---|---|---|
| Yellow | 1.00 | 0.95 | 0.25 |
| Orange | 1.00 | 0.50 | 0.04 |
| Red | 0.85 | 0.08 | 0.01 |
| Green | 0.10 | 0.80 | 0.12 |
| Blue | 0.04 | 0.20 | 0.85 |

**Normalization.** For an amount `a` (0 to 100), the filter's transmittance is
`t^(a/100)`: density in proportion to the amount, as dye in gelatin follows
Beer–Lambert. Filters used together multiply. The weights are `Rec709 × T`,
divided by their sum, so they always sum to 1 and a neutral gray keeps its
level (R4, AC3). Every `t` is above 0, so the sum is never 0. The mix at full
strength:

| Filter at 100 | Weight R | Weight G | Weight B |
|---|---|---|---|
| none (R3) | 0.2126 | 0.7152 | 0.0722 |
| Yellow | 0.234 | 0.746 | 0.020 |
| Orange | 0.371 | 0.624 | 0.005 |
| Red | 0.757 | 0.240 | 0.003 |
| Green | 0.035 | 0.950 | 0.014 |
| Blue | 0.040 | 0.672 | 0.288 |

Red's weight on blue is below Orange's, which is below Yellow's (R5's
assumption). The quick-set value is 100 (`BlackAndWhite.quickSetAmount`, design
§4). If Red or Green at 100 looks too strong on real photos, the table above
should change, not the quick-set value.

**Monochrome caption (design §6).** I built it. The test is
`kCGImagePropertyColorModel == Gray` from the file's header, read off the main
actor while the photo loads. It is never true for a raw.

## Acceptance criteria

| AC | How it is checked | Result |
|---|---|---|
| AC1 (R1, R13) | `offRendersNothing` (off, never used, and turned off render byte-identical to no module, also with other edits). `EditStackCorpusTests` (existing stacks keep their bytes and render hashes). `GoldenTests` (no existing golden moved) | Pass |
| AC2 (R3) | `luminanceMix` on four scenes: R = G = B exactly, and equal to the CPU reference within the derived tolerance (two half-float roundings plus float arithmetic) | Pass |
| AC3 (R4) | `neutralsKeepTheirLevel`: nine mixes, the chart's neutrals and the gray ramp (including values up to 4.0), and the weights sum to 1 | Pass |
| AC4 (R5) | `directions` (each filter's direction on the red, green, blue, yellow and sky patches; Red darkens blue more than Orange, Orange more than Yellow) and `mixesMatchReference` (27 cases against the reference) | Pass |
| AC5 (R2) | `amountsAreRangeChecked`: the model refuses values outside 0 to 100, NaN and infinity; stored values read back unchanged; `photocli`'s parser refuses 150 and −5. The UI field clamps (`SliderRow`) | Pass |
| AC6 (R6) | `quickSets` (one at 100, the rest at 0, on). Debug script: `adjust bw filter red` gives `quickSet red segment 2`; an undo after a quick-set restores the earlier values and on state; choosing the selected one changes nothing (`chooseBlackAndWhite` returns early, and `commit` registers no step without a change) | Pass |
| AC7 (R7, as amended) | `colorMixerFeedsTheMix`: a red luminance −60 darkens the red patch's gray, the gray equals the reference applied to the mixer's color result, and turning the group off gives exactly the mixer-only render. `stepsAfterIt`: Color Grading tints the gray; with Saturation +60 and Vibrance +40 every gray value equals the one without them, within the reference tolerance | Pass |
| AC8 (R8) | `luminanceMix` (gray ramp to 4.0 kept: brightest pixel > 3.9) and `mixesMatchReference` (unclipped, R = G = B) | Pass |
| AC9 (R9) | `everyDecoder`: a JPEG, a raw LibRaw decodes, and the system decoder's DNG when it reads it, through `PreviewGenerator` at full size. On each, the converted render equals the reference applied to that decoder's color render. Render contexts for raw and non-raw give identical results. Videos: batch edits already skip them (`BatchEdit`, unchanged) | Pass |
| AC10 (R10) | `notALocalControl` (no local control of the group's names). `masksWorkOnTheGray` (a mask's exposure and contrast over the conversion keep it gray; outside the mask the result is the global conversion alone) | Pass |
| AC11 (R11) | `presets` (a preset of only this group, a turned-off group stays off, "All settings" replaces it), `paste`, `copiesAndBatches` (virtual copy starts equal and then changes on its own; a preset over two photos is one write with one label each). One undo step for paste and batch is the existing batch path (`changeAdjustments`), unchanged | Pass |
| AC12 (R1, R12) | `stackRepresentation` (on with all filters at 0 is `{on: true}` with a non-identity hash), `checkBox`, `resetIsIdentity`. Debug script History rows: "Turn On Black & White", "Black & White Filter", "Turn Off Black & White", "Reset Black & White" | Pass |
| AC13 (R13) | `pipelineVersionUnchanged` (at least 12: this branch adds no bump; #219 makes it 13). The full `swift test` passes with no existing golden updated; three new goldens | Pass |
| AC14 (R14) | `grainStaysGray` (two grain settings and a vignette: every pixel exactly R = G = B) | Pass |

## Debug-script checks (2026-11-18)

These ran on a copy of the bundle with the identifier `dev.scratch.bwmodule-qa`
and a `photobench` scratch library (4 JPEG, 1 DNG, 100 HEIC). Every launch
passed `--library-root`.

- `adjust bw toggle` on a fresh photo gives `on true applies true`, all filters
  0, `noFilter true`, and the undo name "Turn On Black & White". `adjust bw
  filter red` gives `quickSet red segment 2` and "Black & White Filter".
  `adjust bw off` keeps the values, shows `checkbox off` and segment −1, and is
  named "Turn Off Black & White". `adjust bw reset` returns `on false modified
  false`, named "Reset Black & White". The History panel rows read in that
  order.
- `buttons` with the heading open (Adjust tab scrolled): the check box
  "Black & White" is shown unchecked on a fresh photo (`state off`, tip "Turn on
  Black & White"). After `filter blue` it shows `state on` and the segmented
  control "Filter" shows `selected 4`. After `off` the check box shows `state
  off` and the control shows `selected -1`.
- A snapshot of the loupe after the Red quick-set shows the photo in gray.
- A script note for QA: a `adjust bw …` command that changes nothing (choosing
  the quick-set already in effect, or `print`) still opens the script's own
  undo group, and an empty group counts as an undo step in a script. Check AC6's
  "no undo step" by comparing `print undo` before and after, not by running
  `undo` afterwards. In the app, a click outside the script groups by event, and
  no step is recorded.
- **Not checked by script**: the Adjust ▸ Black & White ▸ menu's enablement and
  check marks. macOS did not make the scripted window key (`key nil` even after
  `open -n` and System Events), so every Adjust item, Auto Exposure included,
  read dimmed. The submenu's title reads enabled, and its first item reads "Turn
  On Black & White".

## For a person (manual checks)

1. Folded on first use; once open, the segmented control, the five tinted
   sliders and the caption match design §3. The tints are legible in light and
   dark mode and with Increase Contrast. The sliders look turned off while the
   group does not apply.
2. Adjust ▸ Black & White ▸ in the loupe: the title follows the state, the
   check marks follow the quick-set and No Filter, and every item is dimmed in
   the grid, while comparing and while cropping.
3. The longest segment names fit at the inspector's narrowest width.
4. Red and Green at 100 on real photos (a blue sky with clouds, a portrait,
   foliage): judge whether the strength is right (design §4).
5. A gray JPEG shows "This photo has no color, so the filters change nothing."
6. Full Keyboard Access reaches the check box, the segments, the sliders and the
   fields.

## Review findings (code-review.md, review.md)

| Finding | Answer | Test |
|---|---|---|
| C1 / F1: a slider gesture that changes no value turned the photo gray and recorded a step | Fixed. `setBlackAndWhite` writes only the value (`Adjustments.setBlackAndWhite`), and a real change switches the group on through `enableModules`. Debug script on a fresh photo: `adjust bw set red 0` leaves `on false modified false` and adds no step; `set red 20` gives `on true` and "Black & White Filter" | `noChangeGestureChangesNothing`: on a never-used photo, `setBlackAndWhite(.red, 0)` changes nothing (the editor's `change` then commits nothing); the same value on a turned-off group leaves it off; a real change still switches it on |
| C2: in `photocli develop`, whether `on` ended up set after a module reset and a filter set depended on the photo's earlier state | Fixed. `EditStack.applying` decides `on` from the edits alone. `on` set or reset by name wins. Otherwise a filter set means on. A module reset or `--reset all` forgets both. With no edit to the group, the stored state stays | `scriptedOnState`: the review's reproduction (`--reset blackAndWhite --set blackAndWhite.green=50`, and `--reset all --set blackAndWhite.red=40`) gives `{on, …}` from both a photo that had the group and one that didn't; plus `on` reset by name, a set wiped by a later reset, edits to other modules, and a filter reset by name |
| C3: `--set blackAndWhite.on=true` did not turn a turned-off group back on | Fixed (cheap): an explicit `on=true` also clears the group's turned-off state, as the heading's Turn On does | `scriptedOnState` (last case) |
| C4: `pipelineVersionUnchanged` hard-coded 12 | Fixed: `>= 12` | — |
| F2: the user guide said "Tone heading"; the paragraph was long | Fixed: "the Light heading's tone sliders", and the paragraph is split in two (what it does and how to use it; its place in the order and what reaches it) | — |
| F3: stale translator comment ("Yellow and Orange are new") | Fixed in `BlackAndWhiteText.name` and the five catalog entries | `LocalizationTests` |
| Designer question in code-review.md (Color Fringes swatches): owner ruling 2026-11-18, the swatches show true colors | Fixed: `LensRenderer.swatch` leaves Black & White out | `fringeSwatchesKeepColor`: the purple slot's swatch with Black & White on equals the one without it, and is purple |

## Rulings (owner, 2026-11-18)

- **RI-1 (R7, render position): keep as built.** The conversion renders right
  after the Color Mixer and before Vibrance, Saturation and Color Grading.
  R7 and AC7 are amended on the issue.
- **RI-2 (R3, weights): keep Rec. 709.** R3 is amended to say so.
- **DQ-1 (a mask's White Balance): keep it tinting the gray.** design.md §6,
  §19.6 and §21 are amended, and R10 records it. The user guide already said so.
- **DQ-2 (the reset arrow): this heading's dimmed reset is right.** The other
  headings' resets staying enabled is a separate bug, which the main session is
  filing.

## Open questions

None left. The entries below are kept as asked, with their rulings above.

### Requirements issues (for the product manager)

- **RI-1 (R7, render position).** R7 asks for the conversion "after the Color
  Mixer and before the tone curve and the rest of the tone group". In the
  renderer, the Color Mixer runs after the tone table (Contrast, Whites,
  Blacks, the Tone Curve), so no position meets both halves of R7. Options:
  - (a) **Built.** Right after the Color Mixer, before Vibrance, Saturation and
    Color Grading. AC7 holds, no existing render changes, and there is no
    clipping in the group. The cost: the tone controls shape each color channel
    before the mix. The composite curve and Contrast give nearly the same gray
    either way. A per-channel Red, Green or Blue curve acts like an extra filter
    instead of tinting the gray (Color Grading does the tinting).
  - (b) Before the tone stage (after White Balance). The Color Mixer would then
    come after the conversion and act on gray, so its luminance would no longer
    move the grays, which breaks AC7.
  - (c) Move the Color Mixer before the tone table only when Black & White
    applies. R7 would hold as written, and photos without the group would not
    change. The cost: two orders in the renderer and the live session. The mixer's
    cube clamps at white, so with Black & White on, highlights above white would
    clip before the tone table could recover them, which works against R8's
    intent.
  - (d) Move the Color Mixer ahead of the tone table for every photo. This
    changes existing renders, so it breaks R13.

  Recommendation: (a), and amend R7 to "after the Color Mixer, before Vibrance,
  Saturation and Color Grading". The user guide already describes (a).
- **RI-2 (R3, weights).** R3 says the mix uses "Rec. 709 weights in the
  working space". The working space is linear Rec. 2020, whose own luminance
  weights are 0.2627, 0.6780 and 0.0593, and the rest of the renderer uses those.
  What is built follows the PRD's wording (Rec. 709). Either is one constant
  (`BlackAndWhite.luminanceWeights`) plus the reference and the three new
  goldens. Recommendation: keep Rec. 709 if the owner meant it; otherwise switch
  to Rec. 2020's weights, which match the rest of the app. Not blocking.

### Design questions (for apple-ui-designer)

- **DQ-1 (§6 and §19.6, a mask's White Balance).** The design says a local White
  Balance has nothing to work on in a converted photo. It does: the masks render
  after the conversion, so a mask's White Balance tints the gray where it
  applies (`maskWhiteBalanceTints`). Local Saturation and Vibrance do nothing.
  The user guide describes what happens. Options: keep it and amend §6, or (with
  the product manager) hide or dim a mask's White Balance while the conversion
  applies. Recommendation: keep it, since it is a way to tone part of a black and
  white photo.
- **DQ-2 (§3.1, the reset button).** I dimmed this heading's reset when there is
  nothing to reset, as the design says and as Spots does. The other headings'
  resets (`AdjustSection`) report themselves enabled even with nothing to reset
  (the `buttons` output on a fresh photo), so this heading looks different from
  its neighbors. This is noted as a proposed follow-up, not changed here.

## Expected conflicts with #219 (Profile group removal)

These are lines both branches are likely to touch. Every one is small.

- `Sources/PhotoCore/Edits/Adjustments.swift`: the `Group` enum's first line
  (this branch split it after `colorMixer`; #219 removes `profile` from it).
- `Sources/PhotoApp/Views/AdjustControls.swift`: `AdjustText.title` switches
  (`.profile` removed, `.blackAndWhite` added, in separate lines).
- `Sources/PhotoApp/Model/AdjustmentEditor.swift`: the `isRaw` comment, which
  mentions Profile, sits near the new `sourceIsMonochrome`; the load task also
  gained one read.
- `Sources/PhotoApp/Model/DebugAdjustCommands.swift`: the header comment lists
  the groups.
- `Sources/PhotoUI/Resources/Localizable.xcstrings`: entries added here may sit
  next to entries #219 removes.
- `docs/USER_GUIDE.md`: the new paragraph follows the raw paragraphs, which
  mention Profile.
- `Sources/PhotoApp/Views/AdjustView.swift`: two added lines between Color Mixer
  and Color Grading. They should merge cleanly against #219's change to
  `DevelopControls`.

## README

No change to requirements, build commands or the repository layout. At Ship,
the feature list needs one line for Black & White.
