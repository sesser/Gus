# Edit and show gain-map photos in HDR: design review

Issue: #282 · Against `design.md` (with §19) and the PRD (issue body, revised
2026-11-25) and the HIG.

| Pass | Reviewed | Verdict |
| --- | --- | --- |
| First, 2026-11-25 | `3c3867f` | Changes needed: F1 to F10 |
| Second, 2026-11-25 | `2e98a11` | Changes needed, narrowly: F1 partly open (at 100%), F11 new (low). F2 to F10 fixed |
| Third, 2026-11-25 | `1f5dd6a` | **Passed**: no open findings |
| Fourth, 2026-11-25 (QA Q2, Q3; DQ-2) | `e1e6fa0` | **Passed**: DQ-2 ruled (a). F12 new, low, not blocking unless M18 fails. Manual checks M1 to M19 are open |

**How this was checked.** By reading the source (and, in the first, second and
fourth passes, `docs/USER_GUIDE.md`). Nothing was built, run or looked at. Test,
snapshot and debug-script results are the engineer's (`status.md`) or QA's
(`qa.md`) and were not re-run. "Pass" below means the code does what the design
says; anything that depends on how it looks or behaves on a screen is "manual".

## Fourth pass

### Verdict

**Passed.** The Q2 and Q3 fixes do what QA asked and match the design as amended
here (§19.6, §19.7). No Requirements issues from design. RI-8 (Undo, Redo,
History revert and Reset All while offline) is with the product manager and is
not judged here; if the ruling changes what those controls offer, it comes back
to design.

### DQ-2

**Option (a), as built** (design §19.6, judgment; the HIG is silent). Centering
gives way before any badge is covered, cut or dropped. Its cost is accepted:
in narrow captions a change of badges, the spinner or the next photo can move
the culling marks. §2.1, §2.2, §4 and §5 are amended to match.

### Q2 and Q3

| Item | Result | What was confirmed in the code |
| --- | --- | --- |
| Q2: choice changeable after an open photo's original went offline | **Fixed**; menu manual (M15) | `AdjustmentEditor.canSetHDR` requires the original online and gates the check box (`AdjustHeader`), the menu item (`LibraryMenuContext`) and `setHDR` itself. The box stays, dimmed, with its stored state; the dimmed menu item reads **Turn On HDR** (§2.2). The engineer's script showed the box dimming and returning; neither run reached the menu |
| Q3: marks covered the version badge at the minimum width | **Fixed** for the cases QA reported; manual (M8) | `ViewThatFits` takes the four arrangements of §19.6 in order; `CenteredCaptionRow` asks for the width that keeps both sides clear of centered marks, and the badge row is fixed-size. Comparison captions are a separate view; QA saw their version badge whole at 760 pt |
| User guide for Q2 and Q3 | Pass | The offline sentence and the narrowest-window sentence match the UI |

### Open finding

**F12 (low; from reading, not seen): nothing gives way after the last
arrangement.** `LoupeCaption`'s fourth arrangement is used even when it doesn't
fit. Its badge row is fixed-size, so with a color label and flag plus two or
more of **Filtered**, **Original**, **Copy** and **Offline** beside the version
badge, at the minimum window with both panes shown, the row looks wider than
the loupe (estimated from type sizes, not measured). `status.md` reports one
such case a few points over, with nothing overlapping. Expected: the ends of the
row (first stars, film strip toggle) run past the loupe, or the color name
squeezes or wraps. A large enough pile-up could reach the version badge, which
R4 and AC4 keep visible. It needs an unusual combination in the smallest window,
and closing a side pane clears it, so it need not hold this branch. **M18
decides:** if the warning mark or **SDR** is cut, anything is drawn over the
sidebar or inspector, or the window or a pane changes width, F12 is to be fixed
on this branch. Otherwise it is a follow-up:

- **Title:** Narrowest loupe caption: many badges make the row wider than the
  loupe
- **Labels:** `bug`. Proposed Complexity: Routine.
- **Body:** At the minimum window (760 pt) with the sidebar and inspector shown,
  open a virtual copy rated 5 stars with a pick flag and a color label, with a
  filter on. Expected: the caption stays inside the loupe, with the version
  badge, **Offline**, stars, flag and color dot whole. Actual (read from the
  code in #282, confirm first): the last arrangement is wider than the caption.
  Fix as #282 design §19.6, "Not covered": drop the film strip toggle, then
  **Copy**, then **Filtered**, and keep the color name to one line. Slug:
  `loupe-caption-narrowest-overflow`.

## Third pass (history, at `1f5dd6a`)

### Verdict

**Passed.** F1 and F11 are fixed, and the change from code-review C9 (zoom and
position kept) is right. No open design findings, no Requirements issues. One
new ruling, design §19.5, and one follow-up, not required for this branch. The
manual checks below are still to be done by a person.

| Item | Result | What was confirmed in the code |
| --- | --- | --- |
| F1 (rest): empty HDR histogram after **Show HDR** at 100% | **Fixed**; manual (M16) | Frames and tiles record the headroom asked for (`requestedHeadroom`), and both skips in `requestRender` require it to match (`LiveFrameRules.isCurrent`). An SDR whole frame of the same values is rendered again in HDR, which makes the counts |
| F11: live frame at 100% kept an old headroom | **Fixed**; manual (M16) | The same rule renders the tile and the whole frame again when the headroom differs by more than the tolerance. The caption spinner ignores headroom, so following the display shows no wait (§6.3) |
| C9: in-place HDR change reset the zoom | Accepted (§19.5); manual (M17) | `beginsVisitInPlace` starts a new visit without resizing the photo or applying zoom, and drops the old tile |
| C8: unreadable original remembered as having no gain map | No design effect | A momentary failure is **SDR: HDR Failed** and the next opening asks again, which makes that help tag true (§5) |

With the mask overlay on, **Show HDR** can still leave the HDR histogram an
empty frame until the overlay is off. That follows §7.2 (overlay frames count
nothing) and is not a finding.

### Follow-up proposed

**Show / Hide HDR and a screen move: a follow-up, acceptable here.** It is older
than this feature, affects every photo, loses no data and no criterion asks for
it. It will be noticed more now that **View ▸ Show / Hide HDR** invites
comparing at high zoom.

- **Title:** Show / Hide HDR and a move to another display return a zoomed loupe
  to 100%
- **Labels:** `bug`. Proposed Complexity: Routine.
- **Body:** In the loupe, zoom to 200% and pan to a corner, then choose **View ▸
  Hide HDR** (or Show HDR), or move the window to another display. Expected: the
  zoom and the place shown stay, as in comparison panes and as when the original
  goes offline or comes back (#282, design §19.5). Actual: the photo returns to
  100%. Any zoom other than fit or 100% is affected, on any photo; older than
  #282. Cause: both paths clear the loupe's shown key (`hdrSetting`, and the
  screen observer's `reload`), so `show` treats the photo as new and applies the
  zoom again. Fix direction: begin a new visit in place (`beginsVisitInPlace`).
  A move between displays of different backing scales must also resize the
  photo for the new scale, keeping the same center. Check fit and 100% don't
  change. Slug: `loupe-zoom-kept-on-hdr-reload`.

## First-pass findings, as confirmed in the second pass

| Finding | Result | What was confirmed in the code |
| --- | --- | --- |
| F1 HDR histogram missing or stale | Fixed (at fit in the second pass, at 100% in the third) | A headroom arriving makes the counts (`hdrDisplayHeadroom.didSet`), and an SDR frame of other values drops them. At 100%: see the third pass |
| F2 SDR or another photo's counts under HDR | Fixed | The inspector draws `HDRHistogramView` with nil counts (frame, no curve, no VoiceOver value) whenever HDR is on screen; comparison clears the counts before counting the new active photo |
| F3 Turn Off HDR flashes the old frame | Fixed | `showLiveFrame` refuses a frame or tile of the other choice, or an HDR one once HDR can't be shown |
| F4 no spinner in comparison | Fixed; manual (M13) | Mini spinner beside the pane's version badge after 0.5 s, same help tag and VoiceOver label, never dropped |
| F5 no sharp HDR frame while picking a fringe color | Fixed; manual (M6) | `SharpeningMapRefiner.render` takes the headroom for the photo refinement; maps ignore it |
| F6 screen gains or loses range in place | Fixed; manual (M12) | Loupe and panes reload when HDR becomes possible or impossible |
| F7 failure leaves HDR under "SDR: HDR Failed" | Fixed | Loupe and pane replace the HDR picture with the SDR renditions and keep the failure |
| F8 offline help tag | Fixed | Text matches §19.1 and is in the String Catalog |
| F9 pane's VoiceOver value | Fixed; VoiceOver by CI only | Pane value has the version phrase; a change of it alone is not announced |
| F10 user guide | Fixed | All four points; also the pane spinner, the empty histogram frame and "only HEIC and JPEG". Terms match the UI |

## Design requirements

| Requirement | Result | Note |
| --- | --- | --- |
| §1 choice and View setting kept apart; verbs | Pass | |
| §1 HLG, PQ, DNG unchanged | Pass | Their badge and tooltip untouched |
| §2.1 check box: system control, after Original, 12 pt, only for gain-map photos, known before the header shows, disabled in crop and once offline, help tag | Pass; look and Tab order manual | M1, M15 |
| §2.2 Adjust menu item: place, titles, dimmed rule (offline included), no shortcut, no toolbar or context item | Pass in code; manual | M1, M15 |
| §2.3 on and off, one undo step and History entry, names | Pass; manual | M2 |
| §2.3 Reset All; presets, paste and Copy sheet leave it alone | Pass | |
| §3 **Show HDR** / **Hide HDR** | Pass | |
| §4 one version badge, states, help tags, fitted rule, symbol and words | Pass | M2, M9 |
| §4 loading spinner after 0.5 s, loupe and panes | Pass; manual | M13 |
| §5 four reasons, order, texts, short form | Pass; short form manual | M8 |
| §5 and §19.4 reason ends, HDR returns; failure stays SDR | Pass; manual | M12, M15 |
| §19.5 zoom and position kept when HDR becomes possible or impossible in place | Pass in code; manual. Show / Hide HDR and a screen move: follow-up | M17 |
| §6.1 arrival changes once; cached HDR first; neighbors preloaded | Pass in code; manual | M2 |
| §6.2 no SDR picture over HDR (release, undo, zoom, drafts, maps keep the range) | Pass in code; manual | M3, M5, M6 |
| §6.3 headroom followed, steady tag | Pass in code, at fit and 100%; manual | M10, M11, M16 |
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
| §19.2 empty frame while counts load; counts made whenever HDR comes on screen | Pass in code; manual | M3, M16 |
| §19.6 narrow caption: four arrangements in order, badges whole, 8 pt from the marks | Pass in code; manual. Beyond the fourth: F12 | M8, M18 |
| §19.7 offline while open: box and menu item dimmed, both return | Pass in code; manual | M15 |

## Improvements (judgment, not required)

- New in the fourth pass: in the widths where the spinner alone tips the caption
  from one arrangement to another, the culling marks move and move back (HDR
  loading, a sharp frame at 100%). If M8 shows it as jumpy, measure the
  arrangements with the spinner's slot always counted.
- Dropped in the fourth pass: the note about badges wrapping under a half-line
  cap. The badge row is now fixed-size.

Carried over from the first pass.

- The crop layer asks the screen for the picture's tag, while the loupe asks for
  the photo's ceiling. If M11 shows the crop picture not getting brighter when
  brightness is raised, ask for the ceiling there too.

## What's working (keep)

- The check box beside **Original** with no control at all on other files; once
  offline it dims in place and keeps its state.
- Marks centered wherever there is room; they move only when the alternative is
  covering a badge.
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
and launch with the command under "For a person" in `status.md`. All can be run
now. VoiceOver, macOS 15 and macOS 26 are left to CI.

| # | Check | Expected |
| --- | --- | --- |
| M1 | Adjust header and **Adjust** menu on a gain-map photo, a raw, a plain JPEG; Tab with Keyboard Navigation on | **HDR** box after **Original**, evenly spaced, only on the gain-map photo; menu title follows the choice, dimmed elsewhere, in the grid, comparing and cropping |
| M2 | Turn HDR on and off, also by Undo, at fit and at 100% | Badge and check mark at once; one change to HDR; off returns to SDR at once with no flash of HDR. At 100%, note any soft or blurry moment in either direction |
| M3 | Step with the arrow keys through several HDR photos and back; watch picture and histogram | At most SDR then HDR once; under an HDR picture the histogram is the HDR one or its empty frame for a moment, never the SDR one or the previous photo's |
| M4 | Crop, mask and spot handles over bright highlights; mask overlay while painting there | Handles findable; the red reads as clearly as in SDR |
| M5 | Crop: enter, straighten, Done, Esc; Edit Spots; Show Original; hover a preset | HDR throughout, no SDR flash; Original is the unedited HDR version |
| M6 | Sharpening map and Fringe Map on and off; pick a filled fringe slot again at 100% | No version badge on a map, no brightness ramp or SDR flash around it; while picking, the HDR picture turns sharp |
| M7 | HDR histogram with and without Increase Contrast, in a Light and a Dark system appearance; Tone Curve | Line, fill, dashed lines and **HDR** mark readable at 88 pt; the curve's backdrop does not change axis |
| M8 | Narrow the window from wide to 760 pt, sidebar and inspector shown, on a 5-star gain-map photo, with **View ▸ Hide HDR**, then as a virtual copy; step to neighbors and turn HDR on and off at the narrowest; same widths in comparison | The badge first takes triangle and **SDR** with the marks centered; only then do the marks move left, after the position, then in its place. Nothing covered; badges whole, on one line; wider again, the marks recenter. Movement of the marks at the narrowest widths is expected (§19.6); note it if it reads as jumpy. In comparison the version badge never drops |
| M9 | On a display that allows less than the photo needs, after a fresh launch: first photo, more photos, grid, video, comparison, window to another display and back | At most one further change about 1.5 s after HDR appears, on the first only; badge **HDR**, help tag with both numbers |
| M10 | Change screen brightness, and drag the window between an HDR and an SDR display, with the photo open and during a slider drag; check the histogram each time | Picture follows with no flash; SDR display shows **SDR: No HDR Display**; HDR and the HDR histogram return |
| M11 | Change brightness during a crop session; switch to another app and back | Crop picture follows; no lasting wrong level or repeated jumps on return |
| M12 | With an HDR photo open, turn the display's HDR off and on in System Settings (external display), in the loupe and in comparison | Picture and badge agree both ways; never "Loading" forever |
| M13 | Comparison of an HDR photo with an SDR one, A to switch; two HDR photos, the first time each is shown; review mode | Each pane its own badge, with a small spinner if HDR takes over half a second; histogram follows the active side without showing the other's counts |
| M14 | Export sheet with one and with several HDR-on photos, plus an issue line if one can be provoked | Notice under the subtitle, above the issue, correct singular and plural |
| M15 | With copies of the photos on an external drive or disk image: eject it with an HDR-on photo open, look at the **HDR** box and the **Adjust** menu, reconnect; open an HDR-off one while ejected | Triangle **SDR** beside **Offline**, no HDR picture; the box stays, dimmed and checked, and the menu item is dimmed as **Turn On HDR**; on reconnect HDR returns, the box is enabled and the item reads **Turn Off HDR**. HDR off: **SDR** and **Offline** if the photo was already known to have a gain map, the help tag not naming Turn On HDR. A photo first opened while ejected may keep an empty histogram until reopened (§19.4) |
| M16 | At 100%: **View ▸ Hide HDR**, wait, **Show HDR**; then, with the mask overlay on and again with Show Original, lower and raise screen brightness on a screen that allows less than the photo needs | The HDR histogram fills within a moment (F1); the picture follows brightness as it does at fit (F11), with no spinner |
| M17 | At 200%, panned to a corner: eject and reconnect the photo's volume; then turn the display's HDR off and on in System Settings (external display) | Same zoom and place throughout; a briefly soft picture is acceptable, and while offline it stays soft. If only the System Settings change returns to 100%, macOS reported it as a screen change: note it on the Show / Hide HDR follow-up under the third pass |
| M18 | At 760 pt with sidebar and inspector shown (a debug-script snapshot can show this): a gain-map photo with 5 stars, a pick flag, a color label (try the longest name), a filter on and **View ▸ Hide HDR**; then press \\ for Original; then a virtual copy of it; then with its volume ejected | F12. Passes the branch if the warning mark and **SDR** stay whole and visible, nothing is drawn over the sidebar or inspector, and no pane or the window changes width. Record what runs past the loupe, wraps or truncates, for the follow-up |
| M19 | **HDR** on for a photo with only Apple's kind of gain map (or the renamed-`tmap` copy, `qa.md` Q1) | It brightens as the other photos do, and the badge **HDR** is true of what is on screen |

## Second pass rulings and findings (history, at `2e98a11`)

- **F1 (rest).** At 100%, **View ▸ Show HDR** or a move to an HDR display left
  the HDR histogram an empty frame until an edit: a frame counted as current by
  its values and overlay alone, so the HDR whole frame was skipped.
- **F11.** Same cause: at 100%, live frames (mask overlay, Show Original) did
  not follow a change of headroom. Low.
- **Ruling §19.4.** HDR returning in place when the original comes back is
  accepted. A photo opened while offline keeps an empty HDR histogram until
  reopened; the follow-up bug proposed in `status.md` covers it.

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
