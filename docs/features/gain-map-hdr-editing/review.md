# Edit and show gain-map photos in HDR: design review

Issue: #282 · Reviewed: branch `feature/gain-map-hdr-editing` at `3c3867f`,
against `design.md` (with §19, added by this review), the PRD (issue body,
revised 2026-11-25) and the HIG. Date: 2026-11-25.

**How this was checked.** By reading the source and `docs/USER_GUIDE.md`.
Nothing was built, run or looked at. Test and debug-script results are the
engineer's (`status.md`) and were not re-run. "Pass" below means the code does
what the design says; anything that depends on how it looks or behaves on a
screen is "manual".

## Verdict

**Changes needed.** The structure, wording, badges, reasons, menus, headroom
memory and export notice match the design. The HDR histogram does not always
describe the picture on screen (F1, F2), which fails R10 and §7.2. F3 to F9 are
smaller; F10 is the user guide.

## Findings for the engineer

Most severe first. All are read from code; none was reproduced.

### F1. The HDR histogram can be missing or out of date (R10, AC9, §7.2)

The editor makes HDR counts only as a by-product of a frame rendered with a
headroom. `hdrDisplayHeadroom`'s `didSet` (`AdjustmentEditor.swift:169`) renders
only while `showsLive`. So when HDR comes on screen from the loupe's side:

- Open an HDR-on photo with **View ▸ Hide HDR**, then choose **Show HDR**: the
  picture is HDR, `hdrHistogram` is nil, and the inspector falls back to the SDR
  histogram (`InspectorView.swift:299`) until the next edit.
- Open it with HDR showing, hide, change Exposure, show: the picture is the new
  edit, the histogram is the HDR counts from before it
  (`AdjustmentEditor.swift:1639` keeps the old value when a frame has none).
- A move from a display without extended range to one with it takes the same
  path.

Fix: make the counts whenever the headroom goes from nil to a value for values
with the choice on, and drop them when an SDR frame replaces other values (§19.2).
To confirm: `hdr off`, open the photo, wait, `hdr on`, wait, `print hdr`
(expected today: `histogram none shows hdr histogram true`).

### F2. SDR counts under the HDR picture on arrival (§7.2, §19.2)

An HDR rendition in memory (a preloaded neighbor, return from comparison or the
grid) is shown at once, but the editor's first frame is asked for 250 ms after it
is ready (`AdjustmentEditor.swift:617`). Until then `InfoHistogram` draws the SDR
thumbnail's counts, then changes axis. §7.2 says the axis changes with the picture
and never falls back to the thumbnail. The same happens in comparison when the
active side first becomes an HDR pane (`comparisonHDRHistogram` is nil while it is
computed), and switching between two HDR panes shows the other photo's counts
until the new ones land (`ComparisonView.swift:338`). Fix per §19.2.

### F3. Turn Off HDR can put the old HDR frame back for a moment (§2.3)

The loupe forgets the shown frame revision whenever it shows cached renditions
(`LoupeView.swift:571`). On **Turn Off HDR** (also its undo or redo and a History
revert) it starts a new visit and shows the SDR preview, then, as the editor is
now live, `showLiveFrame` accepts the editor's last frame, which is still the HDR
one, until the SDR frame is rendered. Expected on screen: SDR, a flash of HDR,
SDR, under an **SDR** badge. Fix: don't show a frame whose HDR choice differs from
the shown one. To confirm: `adjust hdr off`, then `print hdr`; `versions` should
not contain `hdr` for the new visit.

### F4. Comparison panes have no loading spinner (§4, §9)

`ComparisonCaption.swift` has no spinner, so a pane waiting for its HDR version
shows a bare **SDR**, which reads as "this one is off". §4 gives the loupe, review
and each pane the caption spinner after 0.5 s with "Loading the HDR version". Add
it beside the pane's version badge; it follows the badge's never-drop rule only
while loading.

### F5. At 100%, picking a fringe color again never sharpens (§8)

While a filled slot is picked again zoomed in, the sharp frame comes from
`SharpeningMapRefiner`, which takes no headroom (`AdjustmentEditor.swift:956`). The
loupe refuses that SDR frame over HDR (`LoupeView.swift:610`), so an HDR photo
stays soft where an SDR one turns sharp. Fix: give that photo refinement the
headroom (HDR result). Dropping to SDR is not an acceptable fix (R8).

### F6. A display that gains or loses extended range without a window move (§5)

- Single loupe: after **SDR: No HDR Display**, if the same screen reports
  extended range again, `followHeadroom` does nothing (`visitIsGainMap` is false,
  `LoupeView.swift:955`). The badge becomes **SDR** with "Loading the HDR
  version" and nothing loads until the photo is reopened. Reload the photo when the
  reason ends.
- Comparison: when the screen stops reporting it, the panes keep the HDR picture
  under **SDR: No HDR Display** (`ComparisonView.swift:1002`). Reload them, as the
  single loupe does.

Whether macOS changes a screen's potential without also posting a screen change
(for example the HDR switch in System Settings) was not verified; M12 checks it.
The debug script's `hdr display sdr` takes another path and doesn't show this.

### F7. A failure after HDR is on screen leaves HDR under "SDR: HDR Failed" (R4, §5)

`failVisit` (`LoupeView.swift:825`) and `failGainMap` (`ComparisonView.swift:962`)
change the badge but not the picture, and the SDR preview that arrived earlier was
refused. A paste or preset on the open photo whose HDR render fails can leave the
badge naming the version that is not on screen. Show the SDR rendition when the
visit fails.

### F8. Offline help tag points to a dimmed command (§19.1)

`HDRText.help(.sdr)` is used for an offline photo too. Use §19.1's text there.

### F9. Comparison pane's VoiceOver value lacks the version phrase (§12)

`ComparisonController.accessibilityValue(of:)` (`ComparisonView.swift:661`) lists
side, culling and position only. Add the badge's phrase, as the single loupe does,
without announcing a change of it alone. Low: the badge itself carries a label.

### F10. User guide (`docs/USER_GUIDE.md`)

1. "**SDR: HDR Hidden** (**View ▸ Hide HDR** is on)": once HDR is hidden the
   menu item reads **Show HDR**. Say "HDR is hidden; choose **View ▸ Show HDR**".
2. The sentence beginning "When HDR is on but can't be shown" does not parse.
   Say first that a warning sign, **SDR** and a reason show it; then that on a
   narrow line only the sign and **SDR** remain, with the reason in the help tag
   and VoiceOver; then list the four reasons.
3. "The choice can't be changed while the original is offline or while
   comparing" omits that **Reset All Adjustments** in the grid still turns it off
   for an offline photo (RI-2). Cropping also disables it.
4. The second adjustment on arrival: say it normally happens once per display
   each time the app runs, and can happen again if what the display allows has
   changed (R6).

All other terms match the UI: **HDR** check box, **Turn On / Off HDR**,
**Show / Hide HDR**, the badges, the histogram passage, the Export sentence, the
list of adjustments that turn off HLG, PQ and DNG HDR (checked against
`preservesExtendedRange`) and `photocli develop --set hdr.on`.

## Design requirements

| Requirement | Result | Note |
| --- | --- | --- |
| §1 choice and View setting kept apart; verbs | Pass | |
| §1 HLG, PQ, DNG unchanged | Pass | Their badge and tooltip untouched |
| §2.1 check box: system control, after Original, 12 pt, only for gain-map photos, known before the header shows, disabled in crop, help tag | Pass; look and Tab order manual | M1 |
| §2.2 Adjust menu item: place, titles, dimmed rule, no shortcut, no toolbar or context item | Pass; manual | M1 |
| §2.3 on and off, one undo step and History entry, names | **Fail** (F3) | Names and steps pass |
| §2.3 Reset All; presets, paste and Copy sheet leave it alone | Pass | |
| §3 **Show HDR** / **Hide HDR** | Pass | |
| §4 one version badge, states, help tags, fitted rule, symbol and words | Pass; see F8 | M2, M9 |
| §4 loading spinner after 0.5 s | **Fail** in comparison (F4); pass in loupe | |
| §5 four reasons, order, texts, short form | Pass; short form manual | M8 |
| §5 reason ends, HDR returns; failure stays SDR | **Fail** (F6, F7); View setting and display move pass in code | |
| §6.1 arrival changes once; cached HDR first; neighbors preloaded | Pass in code; manual | M2 |
| §6.2 no SDR picture over HDR (release, undo, zoom, drafts, maps keep the range) | Pass except F5's soft picture; manual | M3, M5, M6 |
| §6.3 headroom followed, steady tag | Pass in code; crop and brightness manual | M10, M11 |
| §7.1 histogram drawing, bins, axis, Increase Contrast | Pass; look manual | M7 |
| §7.2 axis with the picture, never SDR counts, comparison, help tag, VoiceOver | **Fail** (F1, F2) | Texts pass |
| §7.3 Tone Curve backdrop SDR | Pass | |
| §8 mask overlay, crop, spots, Show Original, Magnifier, maps | Pass in code except fringe picking (F5); manual | M4 to M6 |
| §9 comparison and review: own badges, never dropped, short form last | Pass, except F4, F7, F9; manual | M8, M13 |
| §10 export notice: place, symbol, plural, count, no button or alert change | Pass; look manual | M14 |
| §11 History labels and revert | Pass | |
| §12 check box and badge labels, canvas value | Pass in loupe; F9 in comparison | VoiceOver by CI only |
| §12 strings in the catalog | Pass | |
| §14 debug script | Pass | |
| §15 user guide | **Fail** (F10) | |
| §18.1 per-screen memory, shared, outside the loupe; lower request keeps it, higher allowance replaces, inactive not kept | Pass (code and AC18 tests); manual | M9 |
| §18.2 potential only decides "has extended range"; low allowance reads **HDR** | Pass | |
| §19.1 offline help tag | **Fail** (F8), new ruling | |
| §19.2 empty HDR histogram while counts load | **Fail** (F1, F2), new ruling | |

## Improvements (judgment, not required)

- The caption now caps every photo's badges at half the line beside the culling
  marks (`LoupeView.swift:1914`), not only gain-map photos'. `CaptionBadge` has no
  line limit, so in a narrow window **Filtered** or **Offline** may wrap or
  truncate in the 28 pt row where they used to run on. Give `CaptionBadge` one
  line and a fixed size, or apply the cap only when there is a version badge. M8
  shows whether it matters.
- The crop layer asks the screen for the picture's tag, while the loupe asks for
  the photo's ceiling (`CropOverlay.swift:101`). If M11 shows the crop picture not
  getting brighter when brightness is raised, ask for the ceiling there too.

## What's working (keep)

- The check box beside **Original** with no control at all on other files.
- One badge, one reason, words plus a warning symbol; low allowance still reads
  **HDR** with the two numbers in the help tag.
- The headroom memory outside the loupe, shared with comparison.
- Maps and the Tone Curve backdrop stay SDR; presets and paste cannot carry the
  choice.
- The export notice as a quiet line, with no alert.

## Manual checks

On an HDR display, with the owner's three photos on the scratch library. Build
and launch with the command under "For a person" in `status.md`. Run them after
F1 to F10 are fixed. VoiceOver, macOS 15 and macOS 26 are left to CI.

| # | Check | Expected |
| --- | --- | --- |
| M1 | Adjust header and **Adjust** menu on a gain-map photo, a raw, a plain JPEG; Tab with Keyboard Navigation on | **HDR** box after **Original**, evenly spaced, only on the gain-map photo; menu title follows the choice, dimmed elsewhere, in the grid, comparing and cropping |
| M2 | Turn HDR on and off at fit and at 100% | Badge and check mark at once; one change to HDR; off returns to SDR at once with no flash of HDR. At 100%, note any soft or blurry moment in either direction |
| M3 | Step with the arrow keys through several HDR photos and back; watch picture and histogram | At most SDR then HDR once; no SDR histogram under an HDR picture |
| M4 | Crop, mask and spot handles over bright highlights; mask overlay while painting there | Handles findable; the red reads as clearly as in SDR |
| M5 | Crop: enter, straighten, Done, Esc; Edit Spots; Show Original; hover a preset | HDR throughout, no SDR flash; Original is the unedited HDR version |
| M6 | Sharpening map and Fringe Map on and off; pick a filled fringe slot again at 100% | No version badge on a map, no brightness ramp or SDR flash around it; the picture sharpens while picking |
| M7 | HDR histogram with and without Increase Contrast, in a Light and a Dark system appearance; Tone Curve | Line, fill, dashed lines and **HDR** mark readable at 88 pt; the curve's backdrop does not change axis |
| M8 | Narrow the window with **View ▸ Hide HDR**, then with a filter active and a virtual copy; same in comparison | Badge takes triangle and **SDR**; never runs into the stars; the version badge never drops; other badges stay on one line |
| M9 | On a display that allows less than the photo needs, after a fresh launch: first photo, more photos, grid, video, comparison, window to another display and back | At most one further change about 1.5 s after HDR appears, on the first only; badge **HDR**, help tag with both numbers |
| M10 | Change screen brightness, and drag the window between an HDR and an SDR display, with the photo open and during a slider drag; check the histogram each time | Picture follows with no flash; SDR display shows **SDR: No HDR Display**; HDR and the HDR histogram return |
| M11 | Change brightness during a crop session; switch to another app and back | Crop picture follows; no lasting wrong level or repeated jumps on return |
| M12 | With an HDR photo open, turn the display's HDR off and on in System Settings (external display), in the loupe and in comparison | Picture and badge agree both ways; never "Loading" forever |
| M13 | Comparison of an HDR photo with an SDR one, A to switch; two HDR photos; review mode | Each pane its own badge; histogram follows the active side without showing the other's counts |
| M14 | Export sheet with one and with several HDR-on photos, plus an issue line if one can be provoked | Notice under the subtitle, above the issue, correct singular and plural |
