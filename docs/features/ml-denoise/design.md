# ML noise reduction for RAW files: design

Owner: apple-ui-designer. Date: 2026-11-05. Status: Designed. RI-1 to RI-7
are ruled (§13): the product manager ruled RI-1 to RI-6 and the owner ruled
RI-7, all on 2026-11-05. prd.md records the rulings (R3–R6, R10, AC4–AC7a,
AC10, Revisions). The engineer's design questions DQ-1 to DQ-3 are ruled in
§15. The owner's ruling on RI-E2 and its effect on wording are in §16.
Nothing is open.

**Inputs.**

- Requirements: [`prd.md`](prd.md) (Approved, owner rulings 2026-11-05),
  cited as R1–R14 and AC1–AC13. This document answers its "Designer" open
  question (§14).
- Earlier design records: [`../ui-redesign/design.md`](../ui-redesign/design.md)
  (placement rules P1–P5, N1, N10, the Activity rule P4) and
  `docs/UI_REDESIGN.md` (UIR §1 caption, §4 inspector, §10 accessibility).
  The sibling feature in the same heading:
  [`../sharpen-mask-preview/design.md`](../sharpen-mask-preview/design.md)
  ("SMP": its caption spinner §5, captions under controls §4).
- Code read at `a3acf1b`: `AdjustView.swift` (DevelopControls `profile`, the
  Decoder pop-up; DetailControls, the Noise Reduction group),
  `AdjustControls.swift` (AdjustSlider and SliderRow with `isEnabled`,
  AppKitCheckbox, AppKitPopUp, GroupLabel, `showsTurnedOff`, AdjustText),
  `EffectsControls.swift` (the missing look-up table's "not applied"
  triangle), `Loupe/LoupeView.swift` (LoupeCaption, CaptionBadge, the
  sharpening map spinner, the canvas's VoiceOver value),
  `Grid/PhotoAccessibility.swift`, `Model/AdjustmentEditor.swift`,
  `Model/BatchActions.swift` (Activity rows for items a batch left alone),
  `PhotoCore/Edits/EditStackRenderer.swift` (`RAWDecodeSettings`),
  `PhotoCore/Edits/Adjustments.swift` (`RawDecode`), `PhotoCore/Edits/AutoAdjust.swift`
  (`RawDefaults`), and `docs/USER_GUIDE.md`.
- HIG pages read on 2026-11-05 (markdown versions): Toggles, Progress
  indicators.

**Clean-room note.** The name, strings, placement and states are this app's
own. I avoided every product term I know other photo apps use for an ML
denoiser ("Denoise", "AI Denoise", "ML Denoise" and the like, and brand names
for denoise engines). "Machine learning" is the generic technical term, used
as a description and not as a product name.

## 1. Name and terms

- **Control:** a check box titled **Use machine learning** in the Noise
  Reduction group. Check boxes are sentence-style (P5). The group label above
  it supplies "noise reduction", so the title doesn't repeat it.
- **In sentences, tooltips and VoiceOver:** "machine learning noise
  reduction". Never "ML" in the interface. It is jargon, and an abbreviation
  VoiceOver reads letter by letter.
- **The decoder:** the Decoder pop-up keeps its version names and marks the
  RAW 9 item "9.dng (machine learning)" (§4). The UI never says "RAW 9". That
  is Apple's internal name for a decoder version, and "9.dng" is already what
  the pop-up shows.
- **Rejected names:**
  - "Denoise" and anything built on it, because other apps use it.
  - "Neural" and "AI", which are marketing words and promise more than a
    decoder option.
  - "Enhanced", which is vague.
  - A pop-up called "Method" with "Standard" and "Machine Learning" items.
    That is two states, and the HIG says: "To present a single setting that
    can be on or off, prefer a checkbox" (HIG Toggles). If the owner later
    adds a model of our own (ruling 1), a pop-up can replace the check box
    then.

## 2. Where the control lives

| Surface | What | Basis |
|---|---|---|
| **Inspector** | Details ▸ Noise Reduction: the **Use machine learning** check box, the first row of the group, above Luminance and Color (§3) | It changes what Luminance means and turns Color off, so it comes before them (a governing control sits above what it governs: HIG Toggles, checkbox hierarchy). R10 puts it in the Noise Reduction group |
| **Decoder pop-up** (Light ▸ Profile) | A second view of the same state: "9.dng (machine learning)" is checked exactly when the check box is (§4) | R3 |
| **Menu bar** | **None** | It is a parameter of a group, like Profile, Decoder or a slider value. ui-redesign N10 keeps parameters in the inspector only. Copy and paste, presets and batch commands already reach it (R10) |
| **Context menu, toolbar, shortcut** | **None** | Same reason. It is set once per photo, not a frequent command, so it gets no shortcut (HIG Keyboards: custom shortcuts for the most frequent commands only) |
| **Loupe caption** | The progress spinner while an ML render is pending (§6), and the **Machine Learning Not Applied** badge when the stack asks for ML here and can't have it (§6) | R6, R8; UIR §1 (the caption holds the loupe's status) |

The inspector edits one photo: the loupe's. In the grid the Adjust tab shows
only Presets ("Open a Photo to Adjust It"). So there is no multi-photo check
box and no mixed state. Selections are reached only through batch commands
(§7).

## 3. Inspector: the Noise Reduction group

### Layout

```
Noise Reduction                                        [✓]   ← group label and group check box (unchanged)
[✓] Use machine learning                                     ← small check box, 22 pt row
    Luminance sets the amount. Color is kept but not         ← caption, 11 pt secondary, wraps,
    used while this is on.                                      aligned with the check box title
Luminance   ──────●────────────────   [  40 ]
Color       ───●───────────────────   [  25 ]                ← unavailable (§5)
```

- **Check box.** A system check box (`NSButton` checkbox) at small control
  size with its title on the trailing side. The title is 11 pt, the size of
  the slider labels. It is leading-aligned with the group's other rows, as
  Paint, Pick Colors and Sharpening Map are. The row is 22 pt high
  (`SliderRow.height`), so the group keeps its row pitch. This extends the
  existing `AppKitCheckbox` with a title. It is not a new control.
- **Caption.** 11 pt `secondaryLabelColor`, wrapping. It is indented to the
  check box title's leading edge, so it reads as that check box's note (HIG
  Toggles: alignment shows grouping). It sits 2 pt below the check box. The
  Luminance row comes 4 pt after it. When there is no caption, the Luminance
  row follows the check box at the group's usual 2 pt.
- **Non-RAW photos** (JPEG, HEIC, TIFF, PNG): there is **no check box and no
  caption**. The group shows Luminance only, as today. This is the app's
  existing rule for RAW-only controls: the Profile group, the Decoder pop-up,
  Color, and Kelvin white balance are all absent for non-RAW files. The
  reasoning is to **hide what can never apply to this file, and dim what
  could apply on another Mac or after a macOS update** (judgment; the HIG
  doesn't decide it for inspectors). A JPEG never becomes a raw. A camera can
  gain support and a Mac can be upgraded. R5 and R7 now say the same: for a
  non-RAW file the control is not offered, and "not RAW" is not a reason
  (RI-3, ruled).

### States

"Asks" means the stack has ML on. "Available" means this Mac's raw decoder
offers 9.dng for this file (§11, one availability rule).

| # | State | Check box | Caption (under the check box) | Color row | Loupe |
|---|---|---|---|---|---|
| S1 | Off, available | Off, enabled | None. The tooltip explains (§9) | As today | As today |
| S2 | On, available | On, enabled | "Luminance sets the amount. Color is kept but not used while this is on." | Unavailable (§5) | Spinner while an ML frame is pending (§6) |
| S3 | Off, not available on this Mac (macOS 15 or 26) | Off, **dimmed** | "Not available on this Mac: it needs macOS 27 or later." | As today | As today |
| S4 | Off, camera not supported (macOS 27) | Off, **dimmed** | "Not available for this camera." | As today | As today |
| S5 | **Asks, not available on this Mac** (R6) | **On, enabled**, so it can be turned off | Orange `exclamationmark.triangle`, then "Not applied on this Mac: it needs macOS 27 or later. Luminance and Color apply instead." | **Available**, because Color applies (§5, RI-2) | **Machine Learning Not Applied** badge (§6) |
| S6 | **Asks, camera not supported** (R6) | On, enabled | Triangle, then "Not applied: this camera isn't supported. Luminance and Color apply instead." | Available | Badge |
| S8 | **Asks, available, but the RAW 9 decode failed** (R5 fourth reason, R6, AC7a) | On, enabled | Triangle, then "Not applied: it could not be applied to this photo. Luminance and Color apply instead." | Available | Badge |
| S7 | Asks, Noise Reduction group turned off | On, enabled. Group-off styling as for the sliders: the group check box is off and the slider fills hide | The S2, S5, S6 or S8 caption, unchanged | **Available**, with the group-off styling: ML is not applied while the group is off (R4 as ruled) | No badge and no spinner: the group asks for nothing while it is off |

Notes on the states:

- **Why S5, S6 and S8 keep the check box enabled.** R6 says only the person
  may remove the setting. A checked box that is dimmed couldn't be unchecked,
  so the person would be stuck with it. Unchecking moves to S3 or S4 (off and
  dimmed), or to S1 after a failure. Undo (⌘Z) brings it back.
- **S8 is learned from a render, not known in advance.** S5 and S6 follow
  from the Mac and the file. S8 appears only when an ML render for the
  current values has failed. Until then the photo is in S2, with the
  spinner. When the failed render's fallback frame arrives, the photo moves
  to S8: the spinner goes, and the caption, badge and Color row change with
  that frame, so nothing claims a state that is not on screen (the same rule
  as SMP §5). The next change of values tries ML again. If that render
  succeeds, the photo returns to S2. Whether to remember a failure for the
  rest of the session, so a slow failing decode isn't repeated on every
  change, is the engineer's call. Return a design question if it changes
  what is on screen.
- **Why S3 and S4 dim the check box instead of letting it be checked.** A
  check box that changes nothing on screen looks broken. The HIG asks that a
  control show its effect. Dimming with the reason next to it says what is
  going on. Batch commands can still give such a raw the setting (§7, RI-4),
  because they carry the group as a whole. That asymmetry is deliberate: the
  inspector offers only what it can show.
- **The triangle** reuses the missing look-up table's "not applied" mark
  (`EffectsControls`: `exclamationmark.triangle`, `.orange`, with "This table
  is missing from the library, so it is not applied."). One look means one
  thing (P5): something you asked for is not in effect. Here the text sits
  beside the symbol instead of in a tooltip only, because R6 requires the
  state to be visible. The symbol is decorative to VoiceOver (§8).
- **Changing the check box while the group is off** turns the group back on,
  as any control does today (`enableModules(changedFrom:)`).
- **Reset.** The Details heading's Reset, the group's own reset path, and
  Reset All Adjustments turn it off (R10). Double-clicking Luminance resets
  Luminance only.
- **Luminance's default.** While ML is on and applied, Luminance's default
  (the fill origin, double-click reset, and the value shown for an unset
  stack) is RAW 9's default for the file. Otherwise it is the current
  decoder's default (PRD "Defaults and sliders"). The number shown can
  change when the box is checked. That is correct: it shows what renders.
- **Undo.** Checking or unchecking is one undo step, named "Turn On Machine
  Learning" or "Turn Off Machine Learning" in the Edit menu (R9, AC9).
  Luminance keeps one step per gesture.

## 4. The Decoder pop-up: one state (R3)

The Decoder pop-up stays in Light ▸ Profile, shown only for raws whose
decoder offers more than one version, as today. It becomes a second view of
the check box's state. It never holds a separate one.

| Situation | Pop-up shows | Choosing in the pop-up |
|---|---|---|
| ML available, off | The decoder in use, as today. Its list includes **"9.dng (machine learning)"** | Choosing 9.dng is the same as checking the box: ML turns on in the Noise Reduction group. One undo step, named "Decoder" (the control used, as today) |
| ML available, on | **9.dng (machine learning)** selected | Choosing any other version turns ML off **and makes that version the Profile group's decoder**, in one undo step named "Decoder" (R3 as ruled). The Profile group's earlier choice is replaced, because the person just chose a decoder |
| ML asks, not available or failed (S5, S6, S8) | The decoder that actually renders: Profile's choice, or the default. The pop-up is **dimmed**, with the tooltip "Turn off Use machine learning to choose another decoder." | Nothing, because it is dimmed |
| ML not available, off (S3, S4) | As today (9.dng is not listed) | As today |
| ML asks, Noise Reduction turned off (S7) | Profile's own decoder choice (or the default), which is what renders | As in the ML-on row: another version turns ML off and becomes Profile's decoder. 9.dng turns the Noise Reduction group back on with ML |

- **The suffix.** The 9.dng item's suffix is what the PRD's problem
  statement asks for: "nothing tells a person that this is the ML denoise".
  It follows the existing "(default)" suffix, which is lowercase and in
  parentheses.
- **"(default)" means the app's default** (RI-7 as ruled). Raws that don't
  ask for ML keep the decoder that was the default before RAW 9, even if a
  future macOS changes Apple's default. The "(default)" suffix goes on that
  pinned version, the one an untouched raw decodes with, so the label stays
  true. It never goes on 9.dng while the pin holds.
- **Why the pop-up is dimmed in S5, S6 and S8.** Picking a decoder there
  would either silently drop ML, which R6 rules out ("the only exception is
  the person turning it off", and a decoder pick is not obviously that), or
  do nothing visible. The check box is the one place that turns it off, and
  the tooltip says so.
- **Group ownership** (RI-1, ruled). ML belongs to Noise Reduction (R3,
  R10). The pop-up shows 9.dng while ML is on and applied. Otherwise it
  shows the Profile group's own decoder choice, which is kept while ML is on
  and comes back when ML is turned off, the same way Color's value comes
  back (R4).
  - Profile-only presets, a paste of Profile, and turning Profile off or on
    never turn ML on or off.
  - Turning Noise Reduction off stops ML in the render and keeps the
    setting (S7).
  - A stack saved before this feature with Profile's decoder at 9.dng opens
    as ML on (the box is checked, the pop-up shows 9.dng), with Profile's own
    choice at the default.
  - A preset saved before this feature with Profile's decoder at 9.dng turns
    ML on when applied. It leaves the target's Luminance and Color as they
    were (§7).

## 5. Color while ML is on (R4)

- **Rule** (RI-2, ruled; R4): Color is unavailable only while ML is on
  **and applied**. That means the stack asks for it, the Noise Reduction
  group is on, ML is available for this file, and the last ML render did not
  fail. Only S2 has Color unavailable. In S5, S6 and S8 Color stays
  available, because the fallback renders the stack's classical values,
  Color included (R6). A dimmed control that still changes the photo would
  be false. In S7 (group off) Color is available with the group-off styling,
  like Luminance.
- **One consequence of S7, accepted.** Changing Color while the group is off
  turns the group back on, as any control does. ML then applies, so Color
  dims with the next frame and the value just set is kept but not used. The
  caption under the check box ("Color is kept but not used while this is
  on") already says so. I don't treat this as an issue: dimming Color while
  the group is off would contradict the ruling, and the case is rare.
- **In S8 the row changes with the fallback frame**, not before (§3). Until
  the failed render's fallback is on screen, the photo is in S2 and Color is
  unavailable.
- **How it looks.** The existing `AdjustSlider(isEnabled: false)`: the
  system's disabled slider, and a value field that can't be edited. The field
  shows the stored value (or the decoder's default when nothing is stored),
  so the person can see it is kept. The row's label and value use the
  system's disabled text color, the way AppKit draws a disabled control's own
  text. UIR §10's "no tertiary text for labels" covers labels of controls
  that are in use. A disabled control is exempt from WCAG contrast, and
  AppKit strengthens the disabled color under Increase Contrast.
  Double-click reset and the row's Reset menu already do nothing while the
  row is disabled (`SliderRow.reset`, `menu(for:)`).
- **Tooltip** on the row (label, slider and field): "Not used with machine
  learning. Your value is kept and applies again when you turn off Use
  machine learning."
- **Turning ML off** brings Color back at its stored value. The stack's
  `color` is unchanged across the round trip (AC5).

## 6. What the loupe shows

### While an ML render is pending (R8)

- **One spinner in the caption.** It is the same system `ProgressView` at
  mini size that the sharpening map uses, in the same slot: after Filtered
  and the Original or Sharpening Map badge, before HDR and Offline (SMP §5;
  HIG Progress indicators: "Display a progress indicator in a consistent
  location"). If the sharpening map is also refining, there is still one
  spinner, labeled for the map.
- **When it shows.** The spinner appears when the loupe has been waiting
  more than **0.5 s** for a frame that decodes with ML. That is the same
  delay as the map's spinner, so a quick render never flickers. The rule
  covers every cause:
  - turning ML on;
  - any change while it is on, including a Luminance drag (there is no
    frame-rate promise, so a slow drag shows the spinner);
  - Undo or Redo;
  - a preset or look-up table hover;
  - arriving at a photo with ML whose preview isn't cached yet.

  It goes away when the ML frame is on screen, when a failed ML render's
  fallback frame is on screen (S8, with the badge), or when the wait ends
  some other way (moving to another photo, turning ML off).
- **No visible label.** The person usually just started the work, and the
  HIG says: "Avoid labeling a spinning progress indicator. Because a spinner
  typically appears when people initiate a process, a label is usually
  unnecessary." The tooltip and VoiceOver label say "Applying machine
  learning noise reduction".
- **The loupe is never blank.** The last frame stays on screen (the
  classical rendition, or the previous ML frame) until the new ML frame
  replaces it in place, with no transition. If the engineer shows a
  classical draft first (an open PRD question about RAW 9 drafts), the
  spinner stays until the ML frame arrives. A draft is not the result.
- **Nothing blocks.** There is no modal state and no disabled controls while
  waiting. Arrow keys, culling keys, the film strip, other sliders and Undo
  all work (AC8). Moving away cancels the pending render. A render that
  finishes for a photo no longer on screen only fills the cache.
- **The inspector shows no second spinner.** One wait gets one indicator,
  in one place. The caption is visible with the inspector hidden, on the
  Info tab, and in review mode.

### When ML was asked for and not applied (R6)

- **Caption badge: Machine Learning Not Applied.** It uses the existing
  `CaptionBadge` and comes after HDR, before Offline. Offline is the other
  "you are seeing a fallback" badge, and the two read together. The tooltip
  gives the reason (§9): this Mac (S5), this camera (S6), or "could not be
  applied to this photo" (S8). The badge shows whenever the values on screen
  ask for ML, the Noise Reduction group is on, and ML did not apply to the
  frame on screen, because it is not available here or because its render
  failed. Hover previews count, as they do for the map's badge.
- **S8 shows with the fallback frame** that follows the failure, never
  before it (§3). A failure during a hover preview shows the badge for that
  preview only. When the hover ends, the badge follows the applied values
  again.
- **Why a badge as well as the inspector caption.** AC7 asks that the loupe
  show it. The badge is also visible in review mode and with the inspector
  hidden or on the Info tab, which is where people look at photos.
- **Offline originals.** The "this Mac" reason doesn't need the file, so the
  badge shows. The camera reason needs the file or its camera model. If the
  engineer can't decide it from the catalog, the badge is left out while the
  original is offline. The Offline badge already says a cached preview is
  shown. S8 never applies offline: nothing is decoded.
- **When ML is on and applied, there is no badge.** The caption marks
  departures from the expected rendering, not settings.

## 7. Batch commands, presets, pairs and export

- **Paste Adjustments, Apply Preset, Reset All** on a grid selection (R10,
  AC10):
  - Every raw the batch reaches gets the setting (RI-4, ruled; R10),
    including raws where it is not available. The setting is kept and the
    photo shows S5 or S6.
  - Non-RAW photos never get it, and their other values still apply.
  - When the batch carried ML on and the selection included non-RAW photos,
    one Activity information row says so: "Machine learning noise reduction
    was left off for N photos that aren't raw files." This follows the
    existing "N videos were left unchanged." row (P4: information, not an
    alert).
- **Preset hover and preset tiles.** Hovering a preset with ML on shows it
  in the loupe with the spinner (§6). Preset tiles render the focused photo
  with ML too, slowly. The tiles' existing placeholder covers the wait, and
  no extra indicator is added.
- **Save Adjustments as Preset…** No change. ML travels with the Noise
  Reduction group's check box in that sheet.
- **Profile-only presets and pastes** never turn ML on or off (RI-1, R3).
- **Presets saved before this feature** whose Profile holds 9.dng (RI-1
  addition, R3): applying one turns ML on in the target. It leaves the
  target's Luminance and Color as they were, so the preset still does what
  it did. On a non-RAW target it does nothing for ML, as for any preset. The
  UI needs nothing new for this. The inspector and the pop-up show the
  result like any ML-on stack, and a batch with non-RAW photos posts the
  same Activity row as above.
- **RAW+JPEG pairs** (R11). Edits stay per file. In the loupe, the pair's
  JPEG shows no check box. A batch command on a pair reaches the file the
  grid shows, as today. AC10 now states that the pair shows its RAW (RI-5,
  ruled).
- **Export** (R12). Export renders ML where available. When ML was asked for
  and not applied for some photos, the export reports it in Activity as
  **information**, one row per reason, posted before the export's own row:
  - "N photos were exported without machine learning noise reduction: this
    Mac needs macOS 27 or later."
  - "N photos were exported without machine learning noise reduction: their
    cameras aren't supported."
  - "N photos were exported without machine learning noise reduction: it
    could not be applied to these photos." For one photo: "…: it could not
    be applied to this photo." (AC7a, RI-6)

  This follows P4 and I3 (background tasks report in Activity, and skips by
  design are information). Without it, an export from the grid on an older
  Mac would silently differ from what the person set (owner ruling 3: "A
  person can always tell…"). I didn't add a note before export in the Export
  sheet's header. It would mean checking each file's camera before the sheet
  opens. It is a possible follow-up.

## 8. Accessibility

### Keyboard and Voice Control

- The check box is a standard control. With Keyboard Navigation or Full
  Keyboard Access on, Tab reaches it after the group check box and before
  Luminance's value field, and Space toggles it. With default settings, Tab
  reaches only text fields, exactly as for every other check box and pop-up
  in the inspector (Profile, Decoder, group check boxes). That is a known
  property of the inspector, not new here.
- Voice Control: "Click Use machine learning". The title is the name.

### VoiceOver

| Element | Label | Value or state | Help |
|---|---|---|---|
| Check box | "Use machine learning" (the visible title) | Checked or unchecked. "Dimmed" in S3 and S4 | S1, S2: the tooltip. S3–S6 and S8: the caption text, so the reason is spoken where the person is |
| Caption | Static text, read in order after the check box | — | — |
| Triangle (S5, S6, S8) | Hidden from VoiceOver. The caption's "Not applied…" says it | — | — |
| Color row (S2) | "Color" (unchanged) | The stored value, "dimmed" | The §5 tooltip |
| Decoder pop-up | "Decoder" (unchanged) | "9.dng (machine learning)" when on | The dimmed tooltip in S5, S6 and S8 |
| Caption spinner | "Applying machine learning noise reduction" | — | — |
| Loupe canvas | Unchanged (file name, kind) | In S5, S6 and S8, the value gains one part after Offline: "Machine learning not applied" (e.g. "Picked, Machine learning not applied, 13 of 87"). The capitalization matches the other parts ("Red label", "Offline") | — |

- **No announcements.** The check box speaks its own new state. A finished
  ML render isn't announced: it changes nothing a VoiceOver user acts on, the
  same rule as the map's refinement (SMP §8). The not-applied state reaches
  VoiceOver through the canvas value. That value changes when the photo
  changes, and the existing value-changed notification covers it.
- The Activity rows (§7) are read like any Activity row.

### Increase Contrast, Reduce Motion, Reduce Transparency, color

- **Increase Contrast.** Every element is a system control or system color:
  the check box, `secondaryLabelColor`, the disabled text color,
  `systemOrange` (`.orange`), `CaptionBadge`'s secondary stroke, and the
  `ProgressView`. All adapt on their own. No new `Palette` colors. The
  library window is dark in every appearance (UIR §10), so the orange
  triangle stays above 3:1 against the inspector. Its meaning is also in the
  text.
- **Color is never the only signal.** "Not applied" is always text (caption,
  badge, VoiceOver value). Unavailable is the system dimmed state plus a
  sentence.
- **Reduce Motion.** Frames swap in place with no transition in any mode.
  The spinner is a progress indicator, not decoration, and stays.
- **Reduce Transparency.** Nothing here is on the glass layer. The
  inspector pane follows the system.
- **Hit target.** The small check box with its title is wider and taller
  than the 20 × 20 pt minimum (UIR §10).

## 9. Strings

All are new, added by hand to `Sources/PhotoUI/Resources/Localizable.xcstrings`.
None contains the product name, so none needs `%@` for a brand value. Counts
are plural variations (stringsdict), as the existing Activity counts are.

| English (key) | Where | Comment for the catalog |
|---|---|---|
| Use machine learning | Check box title (Details ▸ Noise Reduction) | Decodes the raw file with the macOS raw decoder's machine learning model, which reduces noise. Sentence-style: it is a check box |
| Reduce noise with the machine learning model in the macOS raw decoder. Luminance sets the amount; Color isn't used. | Check box tooltip and VoiceOver help, S1 and S2 | |
| Luminance sets the amount. Color is kept but not used while this is on. | Caption, S2 | |
| Not available on this Mac: it needs macOS 27 or later. | Caption and check box help, S3 | |
| Not available for this camera. | Caption and check box help, S4 | The macOS raw decoder's machine learning version doesn't list the camera |
| Not applied on this Mac: it needs macOS 27 or later. Luminance and Color apply instead. | Caption and check box help, S5 | The photo asks for it; the setting is kept |
| Not applied: this camera isn't supported. Luminance and Color apply instead. | Caption and check box help, S6 | Same |
| Not applied: it could not be applied to this photo. Luminance and Color apply instead. | Caption and check box help, S8 | The machine learning decode failed for this file; the setting is kept. "Could not be applied to this photo" is the PRD's reason (R5, AC7a) |
| Not used with machine learning. Your value is kept and applies again when you turn off Use machine learning. | Color row tooltip and VoiceOver help, S2 | "Use machine learning" is the check box title |
| %@ (machine learning) | Decoder pop-up item for the RAW 9 version | %@ is the decoder version, e.g. "9.dng". Pattern of the existing "%@ (default)" |
| Turn off Use machine learning to choose another decoder. | Decoder pop-up tooltip, dimmed (S5, S6, S8) | |
| Turn On Machine Learning | Undo and Redo action name | Title-style, as the other undo names |
| Turn Off Machine Learning | Undo and Redo action name | |
| Applying machine learning noise reduction | Caption spinner tooltip and VoiceOver label | No visible label (HIG Progress indicators) |
| Machine Learning Not Applied | Loupe caption badge, S5, S6 and S8 | Title-style, as the other badges |
| This photo is set to use machine learning noise reduction, which needs macOS 27 or later. It's shown with Luminance and Color instead. | Badge tooltip, S5 | |
| This photo is set to use machine learning noise reduction, which doesn't support its camera. It's shown with Luminance and Color instead. | Badge tooltip, S6 | |
| This photo is set to use machine learning noise reduction, but it could not be applied to this photo. It's shown with Luminance and Color instead. | Badge tooltip, S8 | The decode failed for this file |
| Machine learning not applied | Loupe canvas VoiceOver value part | One part of the list, like "Offline" |
| Machine learning noise reduction was left off for %lld photos that aren't raw files. | Activity information row after a batch command that carried ML on | Plural. Follows "%lld videos were left unchanged." |
| %lld photos were exported without machine learning noise reduction: this Mac needs macOS 27 or later. | Activity information row after an export | Plural |
| %lld photos were exported without machine learning noise reduction: their cameras aren't supported. | Activity information row after an export | Plural |
| %lld photos were exported without machine learning noise reduction: it could not be applied to these photos. | Activity information row after an export | Plural. The "one" variation ends "…: it could not be applied to this photo." (AC7a) |

**Reused, with no new uses:** "Noise Reduction", "Luminance", "Color",
"Decoder", "Offline", "HDR", "Turn On %@" and "Turn Off %@" (the group check
box, unchanged).

**Removed:** none.

## 10. Custom chrome

None. Every element is an existing component or pattern:

- a system check box (`AppKitCheckbox`, given a title);
- a caption `Text`, as under Sharpening Map;
- an SF Symbol in the missing-table style;
- `AdjustSlider` with `isEnabled: false`;
- `AppKitPopUp` with `isEnabled`;
- `CaptionBadge`;
- the system mini `ProgressView`;
- Activity rows.

Nothing goes on the glass layer.

## 11. Notes for the engineer (behavior, not code)

- **One availability rule.** It gives `available`, `notOnThisMac`,
  `cameraNotSupported` or `notRaw` for a file on this Mac. `notRaw` only
  hides the control and is never shown as a reason (R5 as ruled). The check
  box, caption, Color row, Decoder pop-up, caption badge, VoiceOver value,
  Activity rows and `photocli`'s "applied" field (R13) all read it. AC6's
  unit test is on this rule.
- **One render outcome, for the fourth reason.** The result of the last ML
  render for the values on screen (and, separately, of each export) is
  `applied` or `failed`. `failed` gives S8 and the reason "could not be
  applied to this photo", and it reaches the same surfaces as the
  availability reasons. AC7a forces it through a test seam. The debug script
  should be able to force it too, so DR1 can check S8.
  - `notOnThisMac` is "this macOS has no RAW 9", which is a system check and
    needs no file.
  - `cameraNotSupported` is macOS 27 or later with 9.dng missing from the
    file's `supportedDecoderVersions`.
  - The PRD's Intel question decides whether a macOS 27 Mac can lack RAW 9
    entirely. If it can, that is `notOnThisMac`, and the "needs macOS 27"
    wording would be wrong there. Return a design question if so.
- **Three derived facts.**
  - *asks*: ML on in the Noise Reduction group (R3 as ruled).
  - *applied*: asks, the Noise Reduction group is on, `available`, and the
    last render outcome is not `failed`.
  - *Color unavailable*: exactly *applied* (§5, R4 as ruled).

  The badge shows when the group is on, asks is true and *applied* is false.
- **The Decoder pop-up** shows the decoder that renders: 9.dng while
  *applied*, otherwise Profile's own choice or the pinned default. Choosing
  9.dng turns ML on. Choosing another version turns ML off and writes that
  version as Profile's decoder, in the same undo step. It is dimmed in S5,
  S6 and S8 (§4). The "(default)" suffix marks the pinned pre-RAW 9 default
  (RI-7).
- **Spinner.** It is one "waiting for an ML frame for more than 0.5 s" flag
  on the editor, next to `isRefiningSharpeningMap`, and the caption shows one
  spinner when either is set. It is never stored.
- **SliderRow** needs a tooltip (`toolTip` on the row, its slider and field,
  plus VoiceOver help) and the disabled text color when `isEnabled` is false
  (§5).
- **Debug script.** It needs a way to:
  - toggle the check box (`click` on its title should work if it is an
    AppKit button);
  - `print` the check box state and enabled state, the caption text, the
    Color row's enabled state, the Decoder pop-up's selection and enabled
    state, the badge text and the spinner flag;
  - have `accessibility image` show the canvas value part.

  A way to force the availability rule to each value would let DR1 run on
  one Mac. A debug-only override is fine.
- **USER_GUIDE.md.** Describe it in the same change, with the terms in §1
  and §9: Use machine learning, machine learning noise reduction, the Decoder
  pop-up's "9.dng (machine learning)", the Machine Learning Not Applied
  badge, and the spinner. I will check the wording at review.

## 12. Acceptance checks for the designer review

| # | Check | How |
|---|---|---|
| DR1 | States S1–S8: check box state and enabled state, caption text and triangle, Color row availability, per §3. S8 appears with the fallback frame, not before. A JPEG shows no check box and no caption (AC6) | `print` with the availability and render-outcome overrides; manual on screen (glass pane) on macOS 27 and on 15 or 26 |
| DR2 | One state (R3, AC4): checking the box selects "9.dng (machine learning)" in the pop-up. Choosing 9.dng checks the box. Choosing another version while on unchecks it and shows that version as Profile's decoder, in one undo step. A stack saved with `9.dng` before the feature opens checked, with Profile's own choice at the default. A Profile-only preset leaves the box alone. A pre-feature preset with Profile at `9.dng` checks it and leaves Luminance and Color unchanged. In S5, S6 and S8 the pop-up is dimmed with its tooltip. "(default)" is on the pinned version | `print`, `menupress`/`click`, fixture stacks and presets |
| DR3 | Color (AC5): disabled with its value shown in S2, with its tooltip. Available in S5, S6, S7 and S8. Unchecking ML restores it with the same stored value | `print`; manual |
| DR4 | Spinner (AC8): appears only after 0.5 s of waiting for an ML frame, in the caption slot of §6, and goes when the frame arrives. Meanwhile arrow keys, culling keys, the film strip and other sliders work. The loupe is never blank. It is one spinner when the sharpening map also refines | Manual on a 24 MP raw on the owner's Mac |
| DR5 | Badge (AC7, AC7a): "Machine Learning Not Applied" in S5, S6 and S8 after HDR and before Offline, with the tooltip for its reason. It is absent when the group is off and when ML applies. It also shows in review mode | `print`; manual |
| DR6 | Undo (AC9): "Undo Turn On Machine Learning" in the Edit menu. ⌘Z restores the stack | `menuitems "Undo"` |
| DR7 | Batch (AC10): every raw reached gets ML, including raws where it is not available (they show S5 or S6). The Activity row for non-RAW photos appears only when the batch carried ML on. A pair shown as its RAW gets ML on the RAW | Debug script paste on a mixed selection; `print` Activity |
| DR8 | Export (AC7, AC7a): the information rows per reason when ML was not applied, including "could not be applied to this photo" with a forced failure. No row when everything applied | Manual on macOS 26, or with the overrides |
| DR9 | VoiceOver: the check box name, state and help. The Color row dimmed with help. The spinner label. The canvas value part "Machine learning not applied" | Manual; `accessibility image` |
| DR10 | Increase Contrast: no new color, and the triangle, captions and disabled row are legible. Reduce Motion: no transition when the ML frame arrives | Manual |
| DR11 | Strings: every §9 key is present with its comment, plurals for the counts, `LocalizationTests` pass, and USER_GUIDE.md uses §1's terms and never "ML" or "RAW 9" | `swift test --filter LocalizationTests`; reading |

## 13. Requirements issues (ruled)

All seven are ruled. RI-1 to RI-6 were ruled by the product manager on
2026-11-05, and prd.md records them (Revisions; R3–R6, R10, AC4–AC7a,
AC10). RI-7 was ruled by the owner on 2026-11-05, and the product manager is
recording it in prd.md. Nothing is open.

| RI | Ruling | Where this design applies it |
|---|---|---|
| RI-1 | Option A, with an addition. ML belongs to Noise Reduction. Profile's decoder choice applies only while ML is off, and comes back when ML is turned off. Profile presets, a paste of Profile, and the Profile group's on/off never touch ML. Pre-feature stacks holding `9.dng` read as ML on. **Addition:** applying a pre-feature preset whose Profile holds `9.dng` turns ML on and leaves the target's Luminance and Color alone. Choosing any non-9 version in the Decoder pop-up turns ML off and makes that version Profile's decoder | §4 (pop-up table, group ownership), §7 (presets), §11, DR2 |
| RI-2 | As recommended, worded "only while ML is on and actually applied". Color is unavailable only in S2. It is available in the fallback (S5, S6, S8) and while the group is off (S7) | §3 (states table), §5 (rule and the S7 consequence), §11 (*Color unavailable* = *applied*), DR3 |
| RI-3 | As recommended. For non-RAW files the control is not offered, and "not RAW" is no longer a reason | §3, §11 |
| RI-4 | As recommended. Batch commands store ML on every RAW they reach, even where it is not available | §7, DR7 |
| RI-5 | As recommended. AC10 says the pair shows its RAW. R11 is unchanged | §7, DR7 |
| RI-6 | As recommended. A fourth reason, "could not be applied to this photo", with the same fallback as R6. New AC7a | §3 (S8), §5, §6 (badge), §7 (export row), §8, §9 (three strings), §11 (render outcome), DR1, DR5, DR8 |
| RI-7 | Owner: pin the old default. Raws that don't ask for ML keep the pre-RAW 9 default decoder even if a future macOS changes Apple's default. No UI change | §4 and §11: "(default)" marks the pinned version |

The issues as raised:

1. **RI-1. Which group owns the decoder choice?** R10 puts ML in Noise
   Reduction. R3 makes it the same state as the Decoder pop-up, which is in
   the Profile group (`RawDecode.decoderVersion`). The PRD doesn't say what
   these do:
   - a Profile-only preset, or a paste of Profile, onto a photo with ML on;
   - turning Profile off while ML is on;
   - a preset saved before this feature whose Profile group holds `9.dng`.
   - **Option A (recommended):** ML owns 9.dng in Noise Reduction. Profile
     keeps its own decoder choice, which applies only while ML is off, and
     comes back when ML is turned off (like Color, R4). Profile presets and
     paste never turn ML on or off. Turning Profile off doesn't affect ML. A
     legacy `9.dng` in a stored stack or preset reads as ML on, in Noise
     Reduction (R3).
   - **Option B:** ML lives in Profile's decoder field. Then Profile presets
     and paste carry ML and Noise Reduction presets don't, which contradicts
     R10.
2. **RI-2. R4 and AC5 next to R6: is Color unavailable when ML is asked for
   but can't apply?** AC5 says "With ML on, the Color control is
   unavailable". R6 says the fallback renders "the stack's classical values",
   which include Color. A dimmed Color that still changes the photo would be
   false.
   - **Recommended:** Color is unavailable only while ML is asked for and
     available (§5).
   - Otherwise, Color is dimmed in S5 and S6 even though it applies.
3. **RI-3. R5's "the file is not RAW" reason versus R7's "not offered".** AC6
   allows either. The design hides the control for non-RAW files (§3), so
   that reason is never shown in the inspector. It does appear as an
   Activity row after a batch (§7). **Recommended:** reword R5 so the third
   case is "not offered" rather than a named reason, matching R7 and AC6.
4. **RI-4. Batch commands onto raws where ML is not available.** R10 says ML
   "takes effect on RAW files only". It doesn't say whether a raw from an
   unsupported camera, or any raw on macOS 15 or 26, gets the setting stored.
   - **Recommended:** store it (it is a RAW file, and R6's fallback applies),
     so the setting is waiting when the Mac or the camera list catches up.
     The inspector can't turn it on there (S3, S4). That asymmetry is
     deliberate (§3).
   - Otherwise, batch commands leave those raws off.
5. **RI-5. AC10 and pairs shown as their JPEG.** Batch commands reach the
   file the grid shows (`Photo ▸ RAW+JPEG Pair`). AC10 expects "the pair's
   RAW" to get ML, which holds only when the pair shows its RAW (the
   default).
   - **Recommended:** keep R11 as written and state in AC10 that the pair
     shows its RAW.
   - Otherwise, paste would need to reach the RAW of a pair shown as its
     JPEG. That is a change to how pairs work, which R11 rules out.
6. **RI-6. An ML render that fails on a supported file.** R5 lists three
   reasons. If RAW 9 lists the camera but the decode fails (memory, a damaged
   file, a decoder error), the PRD doesn't say what happens. **Recommended:**
   treat it as R6. Render with the default decoder, keep the setting, and
   show S5's treatment with a fourth reason: "Not applied: it couldn't be
   applied to this photo." The badge tooltip and an export Activity row get
   the same reason. That adds three strings to §9 once ruled.
7. **RI-7 (owner, through the product manager). A future macOS that makes
   RAW 9 the default.** The app stores "no decoder choice" as nil, meaning
   the system default (`RawDecode`). If Apple makes 9.dng the default, every
   untouched raw would decode with ML. That breaks R2 ("never changes a
   photo nobody touched") and puts the check box out of step with the
   picture. **Recommended:** the owner decides now whether R2 covers future
   OS defaults. If it does, the engineer pins the pre-9 default for stacks
   that don't ask for ML (a requirement, possibly with a pipeline decision).
   No UI change either way: the check box always shows the stack's request.

## 14. Answers to the PRD's Designer open question

| Question | Answer | Section |
|---|---|---|
| Where the control lives and its name | Details ▸ Noise Reduction, first row: the **Use machine learning** check box. No menu item, context menu, toolbar item or shortcut (a group parameter, N10) | §1, §2, §3 |
| Whether it merges with the Decoder pop-up (R3) | One state with two views. The pop-up's "9.dng (machine learning)" is checked exactly when the box is. Choosing it turns ML on. Choosing another version turns ML off and makes that version Profile's decoder. The pop-up is dimmed when ML is asked for but not applied | §4; RI-1 |
| How Color shows as unavailable (R4) | The system disabled slider and field, with the stored value shown, a tooltip, and a caption under the check box. Only while ML is on and applied; it is available in the fallback and while the group is off | §5; RI-2 |
| Availability and the reasons (R5) | Available: an enabled check box. This Mac or this camera: a dimmed check box with the reason as a caption and help. A failed decode: S8. Not RAW: no control, and not a reason (the app's RAW-only convention) | §3; RI-3, RI-6 |
| "Not applied" (R6) | A checked, enabled box with an orange triangle and the reason (this Mac, this camera, or "could not be applied to this photo"); the **Machine Learning Not Applied** caption badge; a VoiceOver value part; Activity rows after export | §3, §6, §7, §8 |
| Progress while an ML render is pending (R8) | One mini spinner in the loupe caption's existing spinner slot after 0.5 s, with no label, a tooltip and a VoiceOver label. Nothing is blocked and the loupe is never blank | §6 |
| Mixed selection | The inspector edits one photo, so there is no mixed state. Batch commands give raws the setting, leave non-RAW photos off, and post an Activity information row when they did | §2, §7; RI-4, RI-5 |
| Accessibility | Check box name and help, the dimmed Color row with help, spinner label, canvas value part. System colors only. Text always carries state | §8 |
| Strings | 23 new keys, none with the product name | §9 |

## 15. Design questions from implementation (2026-11-05)

Raised by the engineer in [`status.md`](status.md) ("Design questions").
All three are ruled here. I checked them against
`Model/MachineLearningText.swift` and `Localizable.xcstrings`, not on
screen. Seeing them on screen is part of the designer review.

| # | Question | Ruling | Basis |
|---|---|---|---|
| DQ-1 | The singular ("one") forms the engineer wrote for three Activity rows that §9 gives only in the plural | **Approved as written.** "Machine learning noise reduction was left off for %lld photo that isn't a raw file." "%lld photo was exported without machine learning noise reduction: this Mac needs macOS 27 or later." "%lld photo was exported without machine learning noise reduction: its camera isn't supported." Each agrees in number throughout ("photo … isn't a raw file", "its camera"). Each keeps the numeral, like the existing "%lld video was left unchanged." The fourth row's "one" form ("…: it could not be applied to this photo.") follows §9 and AC7a. §9's comments stand. Writing the one forms was the engineer's job, since the catalog needs them | P5 (one pattern for Activity counts); the existing video row |
| DQ-2 | The caption under the check box is indented by the small check box's title inset as AppKit reports it at run time (18 pt in the current design) | **Yes, that is the intent.** §3 says the caption starts at the check box title's leading edge, wherever AppKit draws it. Measuring at run time is better than a fixed number: the box and its gap differ between the current design (macOS 26 SDK on 26+) and the earlier one, and could change in a later release. Keep it measured, not hard-coded. The wrapped caption's second line keeps the same indent. At review I check on screen, in both designs, that the caption's first letter lines up with the "U" of "Use machine learning" and that the triangle (S5, S6, S8) starts at that edge too | HIG Toggles (alignment along the check box shows grouping); §3 |
| DQ-3 | No spinner when arriving at a photo whose preview is already cached. The 250 ms histogram frame doesn't count as waiting | **Matches §6.** The spinner means the picture on screen is not yet the result asked for. A cached preview of the current values is the result, so the person waits for nothing, and a spinner for a background frame would be false feedback (HIG Progress indicators: indicators are for an operation people wait on). Two points follow. (1) If the cached preview is a session-only fallback (S5, S6 or S8, kept in memory per status.md), the badge, caption and Color row must show that state with the cached frame on arrival, again with no spinner. A background frame that retries ML and succeeds swaps in silently and moves the photo to S2. (2) Any later frame the person *does* wait on still follows §6's 0.5 s rule: a change of values, Undo, a hover, or a zoom that needs a new ML render | §6 ("When it shows"); HIG Progress indicators |

**Code changes from §15.** DQ-1 and DQ-2 need none. DQ-3 needs none for
the question asked. Its point (1) is a check: if arriving at a photo whose
cached preview is a session-only fallback doesn't show S5, S6 or S8 (badge,
caption, Color row) with that frame, that is a code change.

## 16. Owner ruling RI-E2: a missing RAW 9 model (2026-11-05)

**Ruling (owner).** The app never starts a download of Apple's RAW 9 model.
A Mac whose RAW 9 model is missing counts as "not available on this Mac":
S3 when the box is off, S5 when the stack asks for ML. The states, the
dimmed check box, the badge and the Activity rows are unchanged.

**One wording consequence (design ruling).** The "this Mac" texts say "it
needs macOS 27 or later". On a Mac already running macOS 27 that lacks the
model, that sentence is false, and it would send the person looking for an
update they already have. On macOS 27 or later, the "this Mac" reason
therefore drops the macOS clause. Below 27, the existing texts stay. I don't
name a fix for a missing model: the app doesn't fetch it, and I won't guess
how macOS does.

| Where | macOS 15 or 26 (unchanged) | macOS 27 or later, model missing (new key) |
|---|---|---|
| Caption and check box help, S3 | "Not available on this Mac: it needs macOS 27 or later." | "Not available on this Mac." |
| Caption and check box help, S5 | "Not applied on this Mac: it needs macOS 27 or later. Luminance and Color apply instead." | "Not applied on this Mac. Luminance and Color apply instead." |
| Badge tooltip, S5 | "This photo is set to use machine learning noise reduction, which needs macOS 27 or later. It's shown with Luminance and Color instead." | "This photo is set to use machine learning noise reduction, which isn't available on this Mac. It's shown with Luminance and Color instead." |
| Export Activity row (plural; the "one" form is "%lld photo was …") | "%lld photos were exported without machine learning noise reduction: this Mac needs macOS 27 or later." | "%lld photos were exported without machine learning noise reduction: it isn't available on this Mac." |

- **These are four new String Catalog keys** (27 in all), with comments
  saying they are for macOS 27 or later without the decoder's model. The
  VoiceOver value part ("Machine learning not applied") and the spinner are
  unchanged.
- **If the app only finds out the model is missing when a decode fails**,
  the photo still shows the "this Mac" state, not S8 ("could not be applied
  to this photo"). It changes with the fallback frame, as S8 does (§3), and
  the export row uses the "this Mac" reason. The availability rule (§11)
  holds `notOnThisMac` for the rest of the session once that is known, so
  every photo says the same thing.
- **Code change: yes.**
  - Add the four keys and choose the text by the running macOS version.
  - Map a missing model to `notOnThisMac`, whether it is known before
    decoding or learned from a failed decode.
  - Add a debug-script way to force "macOS 27, model missing", so DR1 and
    DR8 can check the new texts.

**RI-E3 note (no new ruling).** Camera raws call RAW 9 "9", and DNG files
call it "9.dng" (PRD R3 as amended). The Decoder pop-up's "(machine
learning)" suffix and every rule in §4 apply to both names. If the engineer
already handles "9", this needs no code change.
