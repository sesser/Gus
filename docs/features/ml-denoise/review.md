# ML noise reduction for RAW files: designer review

Owner: apple-ui-designer. Date: 2026-11-05. Step 4 of `docs/WORKFLOW.md`.

**What was reviewed.** `feature/ml-denoise-prd` from `35fa306`, against:

- [`design.md`](design.md): DR1–DR11, the §15 rulings (DQ-1 to DQ-3) and
  §16 (RI-E2);
- [`prd.md`](prd.md): AC1–AC13, with AC7a.

[`status.md`](status.md) is the engineer's record.

**How.** I read the code; I did not run it. The DR verdicts come from the
code, the String Catalog, `docs/USER_GUIDE.md`, and the debug-script results
recorded in status.md. Items marked "on screen" need a person at the bundled
app.

**Code read:**

- `Views/AdjustView.swift`: `decoderPopUp`, `DetailControls`,
  `machineLearningRow`, `noiseSlider`.
- `Views/AdjustControls.swift`: `InspectorMetrics.checkBoxTitleInset`,
  `SliderRow` help and disabled colors, the titled `AppKitCheckbox`.
- `Model/MachineLearningText.swift`.
- `Model/AdjustmentEditor.swift`: `setMachineLearning`, `chooseDecoder`,
  `luminanceNoiseReductionDefault`, the status.
- `Loupe/LoupeView.swift`: `LoupeCaption` badges, `spinnerLabel`, the
  canvas value.
- `Grid/PhotoAccessibility.swift`.
- `Model/AdjustmentActions.swift`: the non-RAW row.
- `Model/ExportModel.swift`: the export rows.
- `PhotoCore/Edits/MachineLearningNoiseReduction.swift`: `Status`.
- `PhotoCore/Edits/AutoAdjust.swift`: `RawDefaults` and the pinned default.

RI-E6 (whether a missing model can be detected) is with the product manager
and outside this review, except where the user guide gets ahead of it (F1).

## Verdict

**The build matches the design. There is one medium fix in the user guide,
three low fixes, and the on-screen checks below.**

The UI follows design.md:

- the placement and states S1–S8;
- the one state shared by the check box and the Decoder pop-up, including
  RI-1's addition and the pinned "(default)";
- Color available only while it applies (RI-2);
- the badge and spinner slots;
- the VoiceOver value part;
- the Activity rows, including §16's macOS 27 texts and DQ-3's arrival at a
  cached fallback.

All 27 strings are in the catalog with comments and plural forms.

None of the fixes blocks the merge. F1 must be fixed before the feature
counts as Shipped, because the guide promises behavior that production
can't deliver yet.

## Design checks

| DR | Result | Notes |
|---|---|---|
| DR1 | **Pass by script; look on screen** | `Status` maps the values, group, availability and last frame to S1–S8. The rules match: `checkBoxIsEnabled` is "asks, or available", and `colorIsAvailable` is `!isApplied`. A JPEG is `.notOffered`, so there is no row. status.md records S1–S8 and the JPEG case by script, with check box, tooltip, caption, triangle and Color row. The triangle is orange, hidden from VoiceOver, and starts at the title's edge (`AdjustView.swift:487–499`). |
| DR2 | **Pass** | `decoderPopUp` selects the machine learning version only while `isApplied`. Otherwise it shows Profile's choice or the default, and lists 9 / 9.dng only where available. `chooseDecoder` is one "Decoder" step and writes Profile's version. "(default)" is on `RawDefaults.defaultDecoderVersion`, which is the pinned version (`AutoAdjust.swift:10–13`, 8.dng by script). The pop-up is dimmed in S5, S6 and S8 with its tooltip. Legacy stacks and presets (RI-1 addition) are covered by tests. Camera raws' "9" was not run on a real file (AC13). See F2 for an edge |
| DR3 | **Pass by script; legibility on screen** | Color is disabled with its stored value and the §5 tooltip, which is on the row, label, slider and field, with VoiceOver help on the slider and field. Label and value use `disabledControlTextColor` (`AdjustControls.swift:268–270`). By script it is enabled in S5–S8 |
| DR4 | **Pass by script; real raw on screen** | One spinner slot after Filtered and the Original or Map badge. The map's label wins (`LoupeView.swift:924–960`). By script, on a 24 MP DNG: off at 0.3 s, on at 0.8 s, and `key right` moved on during the wait. No spinner on arrival with a cached preview (DQ-3). Arrival at a cached fallback shows S8 with no spinner, then moves silently to S2 |
| DR5 | **Pass** | The badge sits after HDR and before Offline (`LoupeView.swift:931–941`), with a tooltip per reason, including §16's macOS 27 text. None in S2 or S7 (script) |
| DR6 | **Pass; ⌘Z on screen** | "Turn On / Turn Off Machine Learning" (`AdjustmentEditor.swift:615`). Scripted launches have no key window, so ⌘Z in the active app is manual |
| DR7 | **Pass by script; pair on screen** | The non-RAW row is information, posted after the writes, only when the batch asked for ML (`AdjustmentActions.swift:62–79`). Script: 3 DNGs got it, 101 others were left off, with one row. A pair shown as its RAW is manual (no pairs in the scratch library) |
| DR8 | **Pass by script; macOS 26 on screen** | The rows come one per reason, before the export's own row (`ExportModel.swift:349–352`). The failed and macOS 27 "isn't available on this Mac" texts were seen by script. The "needs macOS 27" text needs a Mac on 15 or 26, or `ml override macos26` (done by script) |
| DR9 | **Partly by script; VoiceOver on screen** | The canvas value "Machine learning not applied, 3 of 105" comes from `loupeValue(notes:)`. The titled check box leaves its accessibility label to the title (`AdjustControls.swift:799`), so VoiceOver uses "Use machine learning". The script can't reach the inspector's check boxes (an existing limit) |
| DR10 | **On screen** | No new colors in code: system orange, secondary, disabled text color, `CaptionBadge`. No transition on frame swap |
| DR11 | **Pass, with guide fixes** | 27 keys, each with a comment. The four export rows and the non-RAW row have "one" forms (DQ-1). The guide never says "ML" or "RAW 9", and it uses §1's terms. F1, F3 and F4 are wording |

**PRD criteria.**

- Covered by tests or script (status.md): AC1 as ruled (RI-E1), AC2, AC3,
  AC4, AC5, AC7a, AC10 (except the pair), AC11 and AC12.
- AC9 is tested; ⌘Z in the active app is manual.
- Still manual:
  - AC6 on macOS 15 or 26, and on a real unsupported camera;
  - AC7 on macOS 15 or 26;
  - AC8 on a real 24 MP raw;
  - AC10's pair;
  - AC13 (owner).

## Findings

| # | Severity | Finding | Engineer fix? |
|---|---|---|---|
| F1 | **Medium** | **The user guide promises missing-model detection that production doesn't have.** `USER_GUIDE.md:213–216` says it "needs … the decoder's model already on the Mac" and that "'Not available on this Mac' covers both an older macOS and a missing model". Per status.md (RI-E6), nothing in production can detect a missing model. Today a missing model would show as "could not be applied to this photo" or as nothing. Remove both clauses until RI-E6 is ruled and built. Keep "It needs macOS 27 or later … and a camera the decoder supports" | **Yes** (guide). Revisit when RI-E6 is ruled |
| F2 | Low | **The Decoder pop-up can show a single item.** Its visibility tests `defaults.decoderVersions.count > 1` before the machine learning version is filtered out (`AdjustView.swift:204` against `217–219`). When 9 is listed but not available (today only under the missing-model override, later possibly through RI-E6), a file with versions 8 and 9 gets a pop-up with one choice. Test the filtered list's count instead | **Yes** (code) |
| F3 | Low | **Guide wording, "While it is on … Color is dimmed".** Color is dimmed only while ML applies. In the fallback and with the group off, it is available (RI-2). Say "While it applies, **Luminance** sets its amount and **Color** is dimmed". Also use Apple's verbs for check boxes: "select **Use machine learning**" and "deselect it", not "check" and "turn the check box off" | **Yes** (guide) |
| F4 | Low | **Guide timing.** "About 1.4 s for a 24-megapixel photo on an M4 Pro" is a synthetic-file figure for one machine (status.md, R14). It will read as a promise and will age. Say "Rendering with it takes longer, often a second or more" and leave the numbers in the PRD | **Yes** (guide) |
| F5 | Info | **My §8 hit-target sentence was wrong.** The titled check box is the system's small check box, the same as the group check boxes. It is wider than 20 pt because of its title, but not 20 pt tall. That is the inspector's standard control size and needs no change. design.md §8 is corrected | No |
| F6 | Info, accepted | **In S7 the caption says Color is "not used while this is on", while Color is enabled.** This follows from the RI-2 ruling and is recorded in design.md §5 as accepted. The sentence warns that the value won't apply once the group is on. Listed so it isn't reported as a bug | No |

Everything else matches the design as written, and I have nothing further
to raise.

## On-screen checks for the owner

These need the bundled app, active, on the owner's Mac unless noted.
`snapshot` leaves the inspector's glass pane blank, so nothing below has
been seen yet.

| # | Check | Where |
|---|---|---|
| M1 | **Caption alignment (DQ-2).** The caption's first letter lines up with the "U" of "Use machine learning". A wrapped second line keeps that indent. In S5, S6 and S8 the triangle starts at that edge and the text follows 4 pt later. Check at the narrowest inspector width and at a wide one | Owner's Mac (current design). Also macOS 15 for the earlier design, if a Mac is available |
| M2 | **Dimmed Color row with Increase Contrast** (Accessibility ▸ Display). In S2 the label "Color" and its value are readable but clearly dimmed next to Luminance. The disabled slider reads as unavailable. The tooltip shows on hover over the label, slider and field. Also check the dimmed check box and its caption in S3 and S4, and that the orange triangle is visible against the inspector | Owner's Mac, with `ml override` for S3–S5 |
| M3 | **VoiceOver.** The check box speaks "Use machine learning, checkbox", its state, "dimmed" in S3 and S4, and its help (the caption text in S3–S8). The caption is read after it. Color in S2 speaks its value, "dimmed" and the §5 help. The Decoder pop-up speaks "9.dng (machine learning)" when on. The caption spinner speaks "Applying machine learning noise reduction". The loupe canvas value includes "Machine learning not applied" in S5–S8 | Owner's Mac |
| M4 | **Waiting (AC8).** On a real 24 MP raw: the spinner appears after about half a second and goes when the frame arrives. Arrow keys and rating keys work during the wait. The photo never goes blank, and the frame swaps without animation (also with Reduce Motion on) | Owner's Mac |
| M5 | **Keyboard.** With Keyboard Navigation on, Tab reaches the check box after the Noise Reduction group check box and before Luminance's value field, and Space toggles it. ⌘Z undoes "Turn On Machine Learning" (AC9) | Owner's Mac |
| M6 | **Older macOS (AC6, AC7).** On macOS 15 or 26: any raw shows "Not available on this Mac: it needs macOS 27 or later." A stack with ML on shows S5, the badge with the "needs macOS 27" tooltip, and the export row | A Mac on 15 or 26 |
| M7 | **Real cameras (AC6, AC13).** A camera raw from a supported camera lists "9 (machine learning)" in the Decoder pop-up. A camera missing from the decoder's list shows "Not available for this camera." | Owner's files |
| M8 | **Pair (AC10).** Paste onto a RAW+JPEG pair shown as its RAW: the RAW gets ML. Opening the pair's JPEG shows no check box | Owner's library |
| M9 | **Caption line at a narrow window.** "Machine Learning Not Applied" together with HDR, Offline and the film strip toggle doesn't overlap the centered rating, flag and label | Owner's Mac |
