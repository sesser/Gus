# Edit and show gain-map photos in HDR: design review

Issue: #282 · Against `design.md` (with §19) and the PRD (issue body, revised
2026-11-25) and the HIG.

| Pass | Reviewed | Verdict |
| --- | --- | --- |
| First, 2026-11-25 | `3c3867f` | Changes needed: F1 to F10 |
| Second, 2026-11-25 | `2e98a11` | **Changes needed**, narrowly: F1 partly open (at 100%), F11 new (low). F2 to F10 fixed |

**How this was checked.** By reading the source and `docs/USER_GUIDE.md`.
Nothing was built, run or looked at. Test and debug-script results are the
engineer's (`status.md`) and were not re-run. "Pass" below means the code does
what the design says; anything that depends on how it looks or behaves on a
screen is "manual".

## Second pass

### Verdict

**Changes needed.** Nine of the ten findings are fixed. F1 is fixed at fit but,
read from the code, not at 100% and above: **View ▸ Show HDR** there can leave
the HDR histogram an empty frame until the next edit. The same check leaves a
live frame at 100% at an old headroom (F11). Both have one cause and a small
fix. No Requirements issues. One new ruling, design §19.4.

### First-pass findings

| Finding | Result | What was confirmed in the code |
| --- | --- | --- |
| F1 HDR histogram missing or stale | **Partly fixed** | At fit: a headroom arriving makes the counts (`hdrDisplayHeadroom.didSet`), and an SDR frame of other values drops them. At 100%: see below |
| F2 SDR or another photo's counts under HDR | Fixed | The inspector draws `HDRHistogramView` with nil counts (frame, no curve, no VoiceOver value) whenever HDR is on screen; comparison clears the counts before counting the new active photo |
| F3 Turn Off HDR flashes the old frame | Fixed | `showLiveFrame` refuses a frame or tile of the other choice, or an HDR one once HDR can't be shown |
| F4 no spinner in comparison | Fixed; manual (M13) | Mini spinner beside the pane's version badge after 0.5 s, same help tag and VoiceOver label, never dropped |
| F5 no sharp HDR frame while picking a fringe color | Fixed; manual (M6) | `SharpeningMapRefiner.render` takes the headroom for the photo refinement; maps ignore it |
| F6 screen gains or loses range in place | Fixed; manual (M12) | Loupe and panes reload when HDR becomes possible or impossible |
| F7 failure leaves HDR under "SDR: HDR Failed" | Fixed | Loupe and pane replace the HDR picture with the SDR renditions and keep the failure |
| F8 offline help tag | Fixed | Text matches §19.1 and is in the String Catalog |
| F9 pane's VoiceOver value | Fixed; VoiceOver by CI only | Pane value has the version phrase; a change of it alone is not announced |
| F10 user guide | Fixed | All four points; also the pane spinner, the empty histogram frame and "only HEIC and JPEG". Terms match the UI |

### Open findings

#### F1 (rest). At 100%, Show HDR can leave the histogram empty (§19.2, §7.2, R10)

`requestRender` treats a frame as current by its values and overlay only
(`LiveFrameRules.isCurrent`). With the region renderer ready, an SDR whole
frame of the same values counts as current, so the whole frame is skipped
(`AdjustmentEditor.swift:1625`). Region frames carry no counts. So the render
that `didSet` asks for "for the histogram" makes none:

1. **View ▸ Hide HDR**, open an HDR-on photo (or edit one), zoom to 100% and
   wait.
2. **View ▸ Show HDR**.

Expected from the code: the picture returns in HDR (from the loupe's own
renditions) and the inspector keeps the empty HDR frame until an edit. A move
from an SDR display to an HDR one at 100% takes the same path. To confirm by
script: `hdr off`, open the photo, `zoom`, wait, `hdr on`, wait, `print hdr`
(expected today: `histogram none ... inspector histogram hdr empty`).

Fix: a frame is current only if it was also rendered for what is wanted now:
SDR or HDR, and the same headroom. Apply it to the whole frame and the tile (see
F11), or have the counts request bypass the skip.

#### F11. At 100%, a live frame does not follow the headroom (R6, §6.3). Low

Same cause. While live frames stay up (mask overlay, Show Original), a change of
headroom calls `requestRender`, but the tile and the whole frame are "current",
so nothing is rendered; the loupe's own refit skips live frames. At fit the
frame is rendered again. At 100% the picture stays rendered for the old
headroom, left to the system to fit, until the next input. Read from the code,
not run. M16 checks it by eye.

### Ruling

**§19.4.** HDR returning in place when the original comes back is accepted (§5
said "on the next opening"; AC4 allows sooner). Accepted with it: a photo opened
while offline keeps an empty HDR histogram after the volume returns, because the
Adjust tab stays offline until it is reopened. The follow-up bug proposed in
`status.md` ("The Adjust tab stays offline after a photo's volume returns")
should say so and check the histogram.

## Design requirements

| Requirement | Result | Note |
| --- | --- | --- |
| §1 choice and View setting kept apart; verbs | Pass | |
| §1 HLG, PQ, DNG unchanged | Pass | Their badge and tooltip untouched |
| §2.1 check box: system control, after Original, 12 pt, only for gain-map photos, known before the header shows, disabled in crop, help tag | Pass; look and Tab order manual | M1 |
| §2.2 Adjust menu item: place, titles, dimmed rule, no shortcut, no toolbar or context item | Pass; manual | M1 |
| §2.3 on and off, one undo step and History entry, names | Pass; manual | M2 |
| §2.3 Reset All; presets, paste and Copy sheet leave it alone | Pass | |
| §3 **Show HDR** / **Hide HDR** | Pass | |
| §4 one version badge, states, help tags, fitted rule, symbol and words | Pass | M2, M9 |
| §4 loading spinner after 0.5 s, loupe and panes | Pass; manual | M13 |
| §5 four reasons, order, texts, short form | Pass; short form manual | M8 |
| §5 and §19.4 reason ends, HDR returns; failure stays SDR | Pass; manual | M12, M15 |
| §6.1 arrival changes once; cached HDR first; neighbors preloaded | Pass in code; manual | M2 |
| §6.2 no SDR picture over HDR (release, undo, zoom, drafts, maps keep the range) | Pass in code; manual | M3, M5, M6 |
| §6.3 headroom followed, steady tag | **Fail** at 100% with live frames (F11); otherwise pass in code | M10, M11, M16 |
| §7.1 histogram drawing, bins, axis, Increase Contrast | Pass; look manual | M7 |
| §7.2 axis with the picture, never SDR counts, comparison, help tag, VoiceOver | Pass | M3, M13 |
| §7.3 Tone Curve backdrop SDR | Pass | |
| §8 mask overlay, crop, spots, Show Original, Magnifier, maps | Pass in code; manual | M4 to M6 |
| §9 comparison and review: own badges, never dropped, short form last | Pass; manual | M8, M13 |
| §10 export notice: place, symbol, plural, count, no button or alert change | Pass; look manual | M14 |
| §11 History labels and revert | Pass | |
| §12 check box and badge labels, canvas value, strings in the catalog | Pass | VoiceOver by CI only |
| §14 debug script | Pass | |
| §15 user guide | Pass | |
| §18.1 per-screen memory, shared, outside the loupe; lower request keeps it, higher allowance replaces, inactive not kept | Pass (code and AC18 tests); manual | M9 |
| §18.2 potential only decides "has extended range"; low allowance reads **HDR** | Pass | |
| §19.1 offline help tag | Pass; manual | M15 |
| §19.2 empty frame while counts load; counts made whenever HDR comes on screen | **Fail** at 100% (F1) | M16 |

## Improvements (judgment, not required)

Carried over from the first pass.

- The caption caps every photo's badges at half the line beside the culling
  marks, not only gain-map photos'. `CaptionBadge` has no line limit, so in a
  narrow window **Filtered** or **Offline** may wrap or truncate in the 28 pt
  row. Give it one line and a fixed size, or apply the cap only when there is a
  version badge. M8 shows whether it matters.
- The crop layer asks the screen for the picture's tag, while the loupe asks for
  the photo's ceiling. If M11 shows the crop picture not getting brighter when
  brightness is raised, ask for the ceiling there too.

## What's working (keep)

- The check box beside **Original** with no control at all on other files.
- One badge, one reason, words plus a warning symbol; low allowance still reads
  **HDR** with the two numbers in the help tag.
- The headroom memory outside the loupe, shared with comparison.
- The empty HDR histogram frame while counting, never the other version's.
- One rule for "HDR possible", so offline, the View setting and the display
  behave alike in the loupe and the panes.
- Maps and the Tone Curve backdrop stay SDR; presets and paste cannot carry the
  choice.
- The export notice as a quiet line, with no alert.

## Manual checks

On an HDR display, with the owner's three photos on the scratch library. Build
and launch with the command under "For a person" in `status.md`. M16 is expected
to fail until F1 and F11 are fixed; the rest can be run now. VoiceOver, macOS 15
and macOS 26 are left to CI.

| # | Check | Expected |
| --- | --- | --- |
| M1 | Adjust header and **Adjust** menu on a gain-map photo, a raw, a plain JPEG; Tab with Keyboard Navigation on | **HDR** box after **Original**, evenly spaced, only on the gain-map photo; menu title follows the choice, dimmed elsewhere, in the grid, comparing and cropping |
| M2 | Turn HDR on and off, also by Undo, at fit and at 100% | Badge and check mark at once; one change to HDR; off returns to SDR at once with no flash of HDR. At 100%, note any soft or blurry moment in either direction |
| M3 | Step with the arrow keys through several HDR photos and back; watch picture and histogram | At most SDR then HDR once; under an HDR picture the histogram is the HDR one or its empty frame for a moment, never the SDR one or the previous photo's |
| M4 | Crop, mask and spot handles over bright highlights; mask overlay while painting there | Handles findable; the red reads as clearly as in SDR |
| M5 | Crop: enter, straighten, Done, Esc; Edit Spots; Show Original; hover a preset | HDR throughout, no SDR flash; Original is the unedited HDR version |
| M6 | Sharpening map and Fringe Map on and off; pick a filled fringe slot again at 100% | No version badge on a map, no brightness ramp or SDR flash around it; while picking, the HDR picture turns sharp |
| M7 | HDR histogram with and without Increase Contrast, in a Light and a Dark system appearance; Tone Curve | Line, fill, dashed lines and **HDR** mark readable at 88 pt; the curve's backdrop does not change axis |
| M8 | Narrow the window with **View ▸ Hide HDR**, then with a filter active and a virtual copy; same in comparison | Badge takes triangle and **SDR**; never runs into the stars; the version badge never drops; other badges stay on one line |
| M9 | On a display that allows less than the photo needs, after a fresh launch: first photo, more photos, grid, video, comparison, window to another display and back | At most one further change about 1.5 s after HDR appears, on the first only; badge **HDR**, help tag with both numbers |
| M10 | Change screen brightness, and drag the window between an HDR and an SDR display, with the photo open and during a slider drag; check the histogram each time | Picture follows with no flash; SDR display shows **SDR: No HDR Display**; HDR and the HDR histogram return |
| M11 | Change brightness during a crop session; switch to another app and back | Crop picture follows; no lasting wrong level or repeated jumps on return |
| M12 | With an HDR photo open, turn the display's HDR off and on in System Settings (external display), in the loupe and in comparison | Picture and badge agree both ways; never "Loading" forever |
| M13 | Comparison of an HDR photo with an SDR one, A to switch; two HDR photos, the first time each is shown; review mode | Each pane its own badge, with a small spinner if HDR takes over half a second; histogram follows the active side without showing the other's counts |
| M14 | Export sheet with one and with several HDR-on photos, plus an issue line if one can be provoked | Notice under the subtitle, above the issue, correct singular and plural |
| M15 | With copies of the photos on an external drive or disk image: eject it with an HDR-on photo open, reconnect; open an HDR-off one while ejected | Triangle **SDR** beside **Offline**, no HDR picture; HDR returns on reconnect. HDR off: **SDR** and **Offline** if the photo was already known to have a gain map, the help tag not naming Turn On HDR. A photo first opened while ejected may keep an empty histogram until reopened (§19.4) |
| M16 | At 100%: **View ▸ Hide HDR**, wait, **Show HDR**; then, with the mask overlay on and again with Show Original, lower and raise screen brightness on a screen that allows less than the photo needs | The HDR histogram fills within a moment (F1); the picture follows brightness as it does at fit (F11) |

## First-pass findings (history, at `3c3867f`)

Outcomes are in the second-pass table above and in `status.md`, "Review
round 1".

- **F1.** The editor made HDR counts only as a by-product of a frame rendered
  with a headroom, so after **Show HDR** or a display move the HDR histogram was
  missing or out of date.
- **F2.** SDR counts, or the other pane's, showed under an HDR picture until the
  new ones were counted.
- **F3.** **Turn Off HDR**, its undo or a History revert could put the last HDR
  frame back for a moment under an **SDR** badge.
- **F4.** Comparison panes had no loading spinner.
- **F5.** At 100%, picking a filled fringe slot again never sharpened an HDR
  photo.
- **F6.** A display that gained or lost extended range without a window move left
  the badge and the picture disagreeing.
- **F7.** A failure after HDR was on screen left the HDR picture under **SDR: HDR
  Failed**.
- **F8.** The offline **SDR** help tag named a dimmed command (§19.1).
- **F9.** A comparison pane's VoiceOver value lacked the version phrase.
- **F10.** Four wording and completeness faults in the user guide's HDR passage.
