# Edit and show gain-map photos in HDR: design

Issue: #282 · PRD: the issue body (approved 2026-11-24, revised after spike
#285) · Spike: `docs/features/gain-map-hdr/spike.md` · Builds on #277
(`docs/features/heic-exposure-bright/`) · macOS 26 and later only (R18).

The HIG's pages on images and color give no guidance on showing or editing HDR
photos (checked 2026-11-24). Except where a section cites a HIG rule, what
follows is design judgment, not Apple policy.

## 1. Model

A gain-map photo has two things that must never be confused. The UI keeps them
apart by wording and place.

| | Per-photo choice | View setting |
| --- | --- | --- |
| Question it answers | Is this photo edited and shown in HDR? | May this app show HDR on screen at all? |
| Scope | One file or virtual copy; saved with its edits | App-wide preference (`loupe.showsHDR`) |
| Where | Adjust tab check box, **Adjust** menu | **View** menu |
| Verbs | **Turn On HDR** / **Turn Off HDR** | **Show HDR** / **Hide HDR** |
| Undo, History | Yes | No |
| Default | Off | On |

The verbs follow the app's own convention: **Turn On / Off** changes an edit
(**Turn On Black & White**), **Show / Hide** changes what is on screen (**Show
Mask Overlay**). Both are changeable menu labels with a verb (HIG, Menus,
"Toggled items").

The **version on screen** is SDR or HDR. It is HDR only when the choice is on
and no reason in §5 applies.

HLG, PQ and floating-point DNG photos have no choice and change nothing
(R16): same badge, tooltip, histogram and behavior as today. The one change
that reaches them is the View menu's new title (§3). Everything below is about
gain-map photos unless it says otherwise.

## 2. The choice

### 2.1 Check box in the Adjust tab

A system check box titled **HDR** in the pinned header of the loupe's Adjust
tab (`AdjustHeader`), after the **Original** toggle, 12 pt from it. The ⋯
menu stays at the trailing end.

```
[ Original ]   [x] HDR                      (...)
```

- Use `AppKitCheckbox` (the debug script can click it). Not a switch and not a
  bordered toggle button. A checkbox is the macOS control for one on/off
  setting (HIG, Toggles), it matches the Adjust tab's group check boxes, which
  also mean "this edit is on", and it cannot be mistaken for the **Original**
  button beside it, which is a view state and is never saved.
- Not under a heading: the choice belongs to the whole photo, and the pinned
  row keeps it visible beside the histogram it changes.
- Shown only for a gain-map photo. Other files show no control at all, not a
  dimmed one (R1: they have no choice; a dimmed box on every raw would be
  noise). The header's other items don't move.
- Whether the file has a gain map is known by the time the header appears, so
  the box never pops in afterwards.
- Checked state is the stored choice, whatever version is on screen.
- Disabled during a crop session, with **Original**, and once the original of
  an open photo goes offline (§19.7).
- Help tag: "Show and edit this photo in HDR, using the brightness
  information in its file. Exports are SDR."
- The header shows only when the editor is ready, as today, so it is absent for
  a photo opened while its original is offline (RI-2) and while comparing. A
  photo already open when its volume goes keeps the header (§19.7).

### 2.2 Menu bar

**Adjust** menu, first item after the first separator (above **Auto
Exposure**): **Turn On HDR**, or **Turn Off HDR** when the focused photo's
choice is on.

- Enabled: loupe (review as for the other adjust items), editor ready,
  gain-map photo, original online (§19.7), not comparing, not cropping. The rule
  is the one **Adjust ▸ Black & White ▸** uses, plus "has a choice" and the
  online original. Otherwise it stays listed and dimmed with the title **Turn On
  HDR** (HIG, Menus: show unavailable items).
- No keyboard shortcut. It is set once per photo, and the obvious combinations
  are taken or read as system commands.
- No toolbar item and no context menu item. The grid cannot set it (non-goal).

### 2.3 Behavior

- Turning it on: the check mark and badge respond at once; the picture stays
  SDR until the HDR frame is ready, then changes once (§6.1).
- Turning it off: SDR at once.
- One undo step and one History entry per change, both named **Turn On HDR** or
  **Turn Off HDR** (so **Edit ▸ Undo Turn On HDR**).
- Reset All Adjustments turns it off in its existing step, **Reset
  Adjustments**. A photo whose only edit is the choice counts as adjusted for
  Reset All (the ⋯ menu item, **Adjust ▸ Reset All Adjustments**, the context
  menus and the grid batch are enabled for it).
- It counts for nothing else: it does not enable **Save Adjustments as
  Preset…**, it has no row in **Copy Adjustments…**, paste and presets neither
  carry nor change it (R3), and the preset list's check mark ignores it.

## 3. View menu

**Show / Hide HDR Highlights** becomes **Show HDR** / **Hide HDR**. Same
place, same preference, same enabled rule. "Highlights" is no longer true: a
gain map brightens mid-tones too (PRD, Terms). The title is as short as
**Show Original**, and the badge reason **HDR Hidden** (§5) points back to
it. The item covers every HDR photo, gain-map and
otherwise. Hiding keeps all stored choices (R5) and takes effect at once.

## 4. Version badge

In the loupe, review and each comparison pane, a gain-map photo always has
exactly one version badge (`CaptionBadge`), in the slot the **HDR** badge has
now. The exceptions are while a map is shown (§8, RI-4) and an offline photo
with the choice off that the app doesn't know to be a gain-map photo, which
shows only **Offline** (RI-3).

| State | Badge | Help tag |
| --- | --- | --- |
| HDR on screen, not fitted | **HDR** | "Showing the HDR version. This file brightens up to %@× SDR white." |
| HDR on screen, fitted | **HDR** | "Showing the HDR version, fitted to this display. The file brightens up to %1$@× SDR white; the display allows %2$@× now. The histogram shows the whole HDR version." |
| Choice off | **SDR** | "Showing the SDR version. This file also has an HDR version. To use it, choose Adjust ▸ Turn On HDR." |
| Choice on, HDR still loading | **SDR**, with the caption spinner after 0.5 s | "Loading the HDR version" (badge and spinner) |
| Choice on, HDR can't be shown | warning triangle, **SDR** and a reason (§5) | per reason |

- "Fitted" means the headroom the display allows now (§18.2) is below the
  file's, compared at the one decimal the text shows. `%2$@` is that value,
  never the screen's potential. While it isn't known yet, use the unfitted help
  tag, which names only the file. Screen brightness changes this: the help tag
  follows, the badge does not change. Nothing visible announces fitting. On
  many displays it is the normal state, and a mark that came and went with the
  brightness keys would draw the eye away from the photo. The help tag, the
  VoiceOver label and the user guide say it.
- A display with extended range that allows little or none of it at the moment
  (1.3×, or 1.0×) still reads **HDR**, with the fitted text (§18.2).
- The two **SDR** badges without a triangle are normal states. The triangle
  (`exclamationmark.triangle`) marks "you asked for HDR and are not seeing it".
  State is carried by words and a symbol, never by color alone (HIG, Color).
- Changing the badge never resizes the photo. It never moves the culling marks
  either, except in a caption too narrow to keep them centered (§19.6, §20.1).
- HLG, PQ and DNG photos keep today's **HDR** badge and tooltip, and get no
  **SDR** badge.
- The grid and film strip show nothing (non-goal).

## 5. Reasons for SDR when the choice is on

First match wins, so one reason is shown.

| Order | Reason | Badge, full form | Help tag |
| --- | --- | --- | --- |
| 1 | Original offline | triangle **SDR**, beside the existing **Offline** badge | "HDR is on for this photo, but its original is offline, so the cached SDR preview is shown." |
| 2 | **View ▸ Hide HDR** | triangle **SDR: HDR Hidden** | "HDR is on for this photo. To see it, choose View ▸ Show HDR." |
| 3 | Display reports no extended range at all (potential headroom 1, as today's rule; a low current headroom is not this reason, §18.2) | triangle **SDR: No HDR Display** | "HDR is on for this photo, but this display can't show HDR, or HDR is turned off for it in System Settings." |
| 4 | The HDR version could not be made | triangle **SDR: HDR Failed** | "HDR is on for this photo, but its HDR version couldn't be made. Open the photo again to retry." |

- **Offline** adds no second wording of its own: the **Offline** badge, with
  its volume help tag, is the visible reason.
- Short form: where the caption row can't hold the full form, the badge is the
  triangle and **SDR**; the help tag and VoiceOver label keep the reason. In the
  single loupe the row picks the form that fits (`ViewThatFits`), so the badges
  never run into the culling marks. Where the short form doesn't fit beside
  centered marks either, the marks give way (§19.6), and then the caption sheds
  items in a fixed order (§20.1).
- The choice, the check box and the menu item are unaffected by reasons 2 to 4
  and can still be changed. Under reason 1 the check box and menu item can't
  change it, though Reset All from the grid still turns it off (RI-2).
- When a reason ends, HDR returns: at once for the View setting and a display
  move; on the next opening for offline and failure (AC4). For offline, §19.4
  now allows the return in place.
- After a failure the photo stays SDR for the rest of that opening, even if a
  later frame would succeed. Flipping between versions is the fault #277 fixed.
  No alert: the badge is the report.

## 6. What the loupe shows

### 6.1 Arrival (R8, AC7)

1. The cached SDR preview may show first, badge **SDR**.
2. The picture changes once to HDR; badge and histogram change with it.

If an HDR rendition is already in memory (a preloaded neighbor, returning to a
photo, entering or leaving comparison or review), show it first and skip step
1\. Preload neighbors that have the choice on, as HDR neighbors are preloaded
today.

Where the app doesn't yet know what the screen allows, and it turns out to be
less than the HDR picture was rendered for, that picture is fitted again once,
about 1.5 s later (§18.1). It is not a change of version.

### 6.2 While the photo stays open

Once HDR is on screen, no SDR picture of the photo is put on screen unless the
choice changes (RI-1) or a reason in §5 applies. This needs care where today's
code returns to cached renditions:

- On release, the last live frame stays until the settled HDR render replaces
  it. The new edit's cached SDR preview is never shown in between.
- After undo, redo or a History revert that keeps the choice on, the old
  picture stays until the new HDR render is there.
- Zooming to 100% enlarges the HDR picture until the HDR full-resolution render
  or region frame arrives.
- Drafts may be soft, as today. They are HDR.

The layer keeps its extended range for the whole of that time, including while
a map is shown (§8), so the system never ramps the display's brightness down
and up during one visit.

### 6.3 Headroom (R6, R9)

- Render for the headroom the window's display allows now (§18.2, not its
  potential), and follow it when screen brightness changes or the window moves
  to another display, without reopening.
  Nothing in the app animates this; bursts of changes may be coalesced, but the
  picture ends at the latest value. Following is not a change of version: no
  badge change, no spinner, no SDR frame.
- During a drag, frames use the newest headroom.
- What the screen does with a pixel depends only on that pixel and the
  display's headroom, never on the brightest value elsewhere in the frame. An
  edit that pushes some pixels past what the display can show must not dim or
  brighten the rest, during a drag or on release. How (a steady headroom tag,
  clipping at the display's limit) is the engineer's, and the early check
  (§13) judges it.

## 7. Histogram (R10)

The inspector histogram describes the version on screen. With HDR shown it
describes the **whole photo's full HDR version**, at the file's full
brightening, the same on every display. With SDR shown for any reason, and in
the grid, it is today's histogram.

### 7.1 Drawing

Same frame, height (88 pt), colors and peak rule as today.

```
|<------------ SDR, 3/5 ------------>|<---- HDR, 2/5 ----->|
|                                    |    :       :    HDR |
|   ▂▅▇▆▄▃▂▂▁▁                       |▂▂▁ :  ▁    :        |
0                              SDR white   +1      +2     +3 stops
```

- Left three fifths of the plot: 0 to SDR white, on the same display-encoded
  scale as today.
- Right two fifths: 0 to +3 stops above SDR white (1× to 8×), linear in stops.
  The range is fixed, never fitted to the file, the edit or the display, so
  the axis means the same thing during a drag, after release, on every display
  and from photo to photo. 3 stops covers the files measured (headroom up to
  6.3×).
- 255 bins of equal width: 153 SDR, 102 HDR. A value of exactly SDR white falls
  in the last SDR bin; values past +3 stops collect in the last bin. As today,
  the first and last bins don't set the height scale.
- Channels are binned from linear Display P3 relative to SDR white.
- A small step in the curve at the line is expected (the two scales differ by
  about 1.4 there). Don't smooth or renormalize it.
- A solid 1 pt line at SDR white (white, 45% opacity; 80% with Increase
  Contrast), a faint fill over the HDR part (white, 6%), dashed lines at +1 and
  +2 (white, 15%), and **HDR** in the caption 2 style (10 pt, white, 60%) at
  the top trailing corner. The line and the word, not a color, say that the
  axis changed.
- No marker for the display's headroom: the histogram must look the same at any
  headroom (AC9).
- An edit that leaves nothing above white keeps the HDR axis with an empty
  right part (R8).

### 7.2 Behavior

- The axis changes only when the version on screen changes: on arrival, together
  with the picture. Once HDR is on screen the histogram never falls back to the
  SDR thumbnail's counts, including after release while the new render is
  pending: it keeps the last HDR counts.
- Update timing is today's (live while dragging; may lag until a pause at
  100%). If R11 forces fewer updates during a drag, keep the HDR axis and update
  less often.
- With an HDR-on photo in the active comparison pane, the histogram is the HDR
  one, on both tabs. It follows the active side.
- Show Original: the unedited HDR version's. Maps and mask overlay frames count
  nothing, as today; the last photo counts stay.
- Help tag (HDR only): "The whole photo's HDR version. Right of the line is
  brighter than SDR white, up to 3 stops; anything brighter collects at the
  right edge. A picture fitted to the display can differ."
- VoiceOver: label "Histogram, HDR version", value "%lld percent of the photo is
  brighter than SDR white" (by luminance). SDR keeps "Histogram".

### 7.3 Tone Curve backdrop

The histogram drawn behind the **Tone Curve** stays the **SDR** version's, in
the same shape as today, also while HDR is shown. The curve's horizontal axis is
the SDR tones it works on (R7); an HDR histogram behind it would put each tone
under the wrong part of the curve. If computing it live breaks R11, it may
update on pause. It must never show HDR counts.

## 8. Modes and overlays

"HDR" below means the HDR version fitted to the display, in an extended-range
layer.

| Mode | Picture | Version badge | Notes |
| --- | --- | --- | --- |
| Fit, 100% and above, pan | HDR | HDR | |
| Slider, curve, wheel, mask or brush drag | HDR frames | HDR | §6.2 |
| Hover preview (preset, look-up table) | HDR version of the previewed values | HDR | Presets don't carry the choice, so it stays |
| Show Original | Unedited HDR version | **Original** and HDR | R8 |
| Mask overlay, painting included | The photo with today's red tint, then brightened like the photo | HDR | See below |
| Sharpening map, Fringe Map | The map as today: SDR values, not brightened | None; the map's badge only | See below |
| Crop session | The whole-sensor picture under the crop frame in HDR | HDR | See below |
| Edit Spots | HDR | HDR | Overlay drawing unchanged |
| Fringe picking | HDR | HDR | The Pixel Magnifier's plate and readout stay SDR |
| Film strip, grid, preset thumbnails, look-up table browser, export previews | SDR | none | R12 |

- **Mask overlay.** The tint is applied to the SDR render and the file's
  brightening follows, so red-to-photo proportions, and therefore how clearly
  coverage reads, are those of the SDR overlay at every brightness. A tint at
  SDR brightness laid over a highlight several times brighter would nearly
  vanish exactly where it is needed. The overlay is never a reason to drop to
  SDR.
- **Maps.** A map is a diagnostic drawing, not a version of the photo: gray
  values that mean coverage. Brightening it by the gain map would make equal
  coverage look unequal. It is shown as today in the still extended-range layer,
  and the picture returns straight to HDR when it ends (RI-4).
- **Crop.** The image under the frame (`cropImage`) is the HDR version, follows
  headroom, and shows without an SDR frame first: entering Crop keeps the
  current picture until the HDR whole-sensor render is ready. The dimming
  outside the frame, the frame, handles and grid are drawn as today, at SDR
  brightness. Done and Esc return straight to HDR.
- **Handles** (crop, mask, spot) stay SDR white with their existing outlines.
  Check they stay findable over bright highlights (M list, §13).
- **Pixel Magnifier.** It reports the SDR picture's pixels and values, which
  are what picking and the controls work on. No change.

## 9. Comparison and review

- Each pane shows its own photo's choice, with its own version badge (R4). An
  HDR photo beside an SDR one is a normal pairing; nothing matches them.
- Pane captions, short of room, drop the position, then middle-truncate the
  name, as today, then switch a §5 badge to its short form. A gain-map photo's
  version badge never drops. HLG, PQ and DNG photos' **HDR** badge may still
  drop, as today. One further step comes after these: the compact rating
  (§20.2).
- While comparing, the choice can't be changed (no editing while comparing).
- Review mode is the loupe: same badges, headroom and reasons.

## 10. Export notice (R13)

In the Export sheet's fixed header, a line under the subtitle, shown when at
least one photo being exported has the choice on:

- SF Symbol `info.circle`, 11 pt secondary text, laid out like `IssueText`.
- "1 photo has HDR on. Exports are SDR." / "%lld photos have HDR on. Exports
  are SDR." (plural variations in the catalog).
- Counted over the sheet's frozen photos (videos excluded), whatever the View
  setting or display, and known when the sheet appears.
- It sits above any general issue line. It changes no button and no default, and
  there is no alert (HIG, Alerts: "Use alerts sparingly" and "Avoid using an
  alert merely to provide information"). The line is information in the context
  where it matters.

## 11. History

Entries **Turn On HDR** and **Turn Off HDR**, like any group's. Reset All's
entry is unchanged. Reverting to an entry writes that entry's choice with its
other edits, so reverting to a state from before HDR was turned on, including
any entry older than this feature, turns HDR off (RI-1).

## 12. Accessibility

- Check box: label "HDR", the §2.1 help tag as its hint. Full keyboard access
  reaches it in the header after **Original**.
- Version badges have spoken labels that stand alone, not the bare letters:
  "Showing the HDR version" (plus ", fitted to this display", under §4's rule
  for "fitted"), "Showing the SDR version", "Loading the HDR version", and "HDR
  is on, showing the SDR version:" followed by "original offline", "HDR is
  hidden in the View menu", "this display can't show HDR" or "the HDR version
  couldn't be made".
- The loupe canvas's accessibility value includes the same phrase. A change is
  not announced on its own.
- Histogram as §7.2.
- No motion is added, so Reduce Motion needs nothing. Increase Contrast: §7.1.
- Strings go in the String Catalog.

## 13. Early check by eye (before the rest is built)

The PRD's condition on Q2. With only enough built to show and drag one file in
HDR, the owner looks, on the HDR display:

- E1. A file brighter than the display (the Pixel sample, or an iPhone photo at
  reduced display headroom): does the fitted picture look acceptable?
- E2. Drag Exposure up and down, Contrast, and Sharpening to its maximum: does
  anything away from the edit shift in brightness during the drag or on
  release?
- E3. Change screen brightness with the photo open: does it follow without a
  jump, a flash of SDR or a lasting wrong level?
- E4. Open the photo from the grid: is the one SDR-to-HDR change acceptable?

If E1 or E2 fails, Q2 goes back to the owner before more is built. The final
manual checks (in `review.md`) will add: handles over highlights, the mask
overlay's legibility, the crop session, maps, the histogram's look in both
appearances, narrow captions, and, on a screen that allows less than the photo
needs, the second change on arrival (§18.1) and the badge and help tag there
(§18.2).

### 13.1 Result (2026-11-25)

The owner ran the check and reported, in full:

> "All four pass. The built-in display showed 2.6x I think. It looks good and
> works as it should"

**What it says.** E1 to E4 pass, and the owner finds that it looks good and
works as it should. E1 and E2 did not fail, so Q2 stands and the rest may be
built.

**What it does not say.**

- "2.6x" is from memory ("I think"), and the photo it was read on is not named.
  The files' ceilings are 2.6×, 3.7× and 4.6×: read on IMG_0546 it would mean
  an unfitted picture, on either of the other two a fitted one. It is not
  recorded as a measurement.
- Whether the owner used the external Dell display.
- Which display and photo each check was run on, and how E3 changed the
  headroom.
- Anything about the second change on arrival that E4 asked about (DQ-1). The
  E4 pass is not recorded as acceptance of it. The owner was asked separately
  later the same day and accepted it (RI-6, §17; §18.1).

## 14. Debug script

For AC4, AC5, AC7 and AC9 without a person (names are suggestions):

- `adjust hdr on|off`: the per-photo choice. The existing `hdr on|off` stays the
  View setting.
- `hdr display <headroom>|sdr|system`: overrides what the loupe takes as the
  headroom the display allows now (as a settled reading, so the fitted texts can
  be checked), or that it has no extended range.
- `print hdr` adds, per shown photo or pane: has a choice, choice, version on
  screen, badge text, help tag and reason, file headroom, the screen's potential,
  the headroom allowed now (or unknown), the headroom rendered for, refits,
  histogram kind (SDR or HDR) and its share above white.
- A log of version changes for the open photo, so AC7 can show at most one.

## 15. User guide

Replace the second paragraph of **HDR** (gain-map photos stay SDR) and add to
it, in these terms:

- Which files: most iPhone HEIC and JPEG photos and Ultra HDR JPEGs. Off by
  default; **HDR** check box in the Adjust tab or **Adjust ▸ Turn On HDR**; an
  undoable edit; not carried by presets or Copy Adjustments; Reset All turns it
  off.
- What changes: edits apply to both versions alike; the controls work on the SDR
  tones; there is no strength control.
- The badges and the four reasons; fitting to the display; the histogram's two
  parts, and that it shows the full version; the Tone Curve's backdrop is SDR.
- How much extra brightness a display allows depends on the display, its
  settings and brightness, and whether the app is in front. When it allows
  little, HDR looks close to SDR; the badge still says **HDR**, and its help tag
  gives the file's number and the display's. The first HDR photo shown on a
  display may adjust its brightness once, a moment after it appears.
- Thumbnails, previews and exports are SDR.
- **View ▸ Show / Hide HDR** replaces **Hide HDR Highlights**.
- The existing HDR paragraph stays for HLG, PQ and DNG, and says that their HDR
  view turns off with some adjustments and that this does not happen to
  gain-map photos (R16). Name those adjustments as they are today: Contrast,
  Whites, Blacks, Highlights above 0, Tone Curve, Color Mixer, Color Grading, a
  look-up table, Dehaze, Grain (check against `preservesExtendedRange`).
- Add to the histogram and Export passages where they stand.

## 16. Answers to the PRD's designer questions

| Question | Answer |
| --- | --- |
| Does anything say the picture is fitted and differs from the histogram? | The **HDR** badge's and histogram's help tags, VoiceOver and the user guide. Nothing visible (§4, §7.1) |
| Where the choice lives | **HDR** check box in the Adjust header; **Adjust ▸ Turn On / Off HDR** (§2) |
| How the loupe states version and reason | One version badge; triangle and reason when blocked (§4, §5) |
| Name of Show / Hide HDR Highlights | **Show HDR** / **Hide HDR** (§3) |
| Histogram above white | SDR three fifths, +3 stops two fifths, fixed axis (§7) |
| Mask overlay, maps, Show Original, crop | HDR except the maps, which stay as today (§8) |
| Where the export notice appears | Export sheet header (§10) |
| History label | **Turn On HDR** / **Turn Off HDR** (§11) |

## 17. Requirements issues and their rulings

None is open. RI-6 and RI-7, raised after the early check, were settled on
2026-11-25: RI-6 by the owner, RI-7 by the product manager's clarification,
which the owner can overrule. The design above follows each.

- **RI-1. R8 against R2.** R8 says undo and History revert never switch to SDR;
  R2 makes the choice an undoable edit kept in History. *Settled:* R8 holds
  while the choice stays on. Toggling the choice, undo or redo of the toggle,
  and Reset All change the version, because the person asked. The owner also
  ruled on 2026-11-24 (PRD Q3) that a History revert restores that entry's HDR
  setting, so reverting to a state from before HDR was turned on turns it off.
- **RI-2. Assumption 1 against offline originals.** Only the loupe's Adjust tab
  is unavailable for an offline photo. Grid batch commands that don't read the
  original (paste, presets, Reset All) still reach it (`BatchEdit`). *Accepted
  by the product manager:* the check box and **Adjust ▸ Turn On / Off HDR** can
  change the choice while SDR is shown for the View setting, the display or a
  failure, not while the original is offline. Reset All from the grid turns the
  choice off for an offline photo too; paste and presets leave it alone (R3).
- **RI-3. R4 for offline photos with the choice off.** The app may not know
  without the file whether it has a gain map. *Ruled by the owner on 2026-11-24
  (PRD Q4):* with HDR off and the original offline, the loupe may show only
  **Offline**. It shows the **SDR** badge too if the app already knows it is a
  gain-map photo. No migration or re-reading of the library is asked for this.
  With the choice on it is always known.
- **RI-4. R4 and R8 during the maps.** The sharpening and fringe maps are
  neither version. *Accepted by the product manager:* they show as today,
  without a version badge, and the HDR picture returns when they end; this is
  not a switch to SDR. The Pixel Magnifier's plate stays SDR.
- **RI-5. R4 in narrow captions.** *Accepted by the product manager:* a full
  reason may shorten to the warning triangle and **SDR**, with the reason in the
  help tag and VoiceOver.
- **RI-6. R6, R8 and AC7 against the second change on arrival.** The screen's
  headroom can only be read once the app asks for extended range, and the
  reading takes 1 to 2 s. Until then the system, not the gain map's rule, fits
  a picture the screen can't show in full, and the app then fits it again.
  *Ruled by the owner on 2026-11-25: accepted.* Asked whether the second change
  is acceptable, with the default "accept it, limited to rare cases (normally
  once per screen each time the app runs), checked again in the final manual
  checks" and the alternative of delaying HDR about 1.5 s on the first photo of
  such a screen, the owner answered, verbatim: "Yes, Accept it. I did notice it
  in fact. It's fine". In the PRD: R6 states the allowance and its limit, R8 and
  AC7 say it is not a change of version, AC18 tests that it stays rare.
- **RI-7. R4 and R5, "a display without extended range".** A screen can report
  extended range and allow almost none of it (measured: potential 4.18, allowed
  1.29; potential 16, allowed 9.82; an app that isn't in front may be given
  less, #287). *Clarified by the product manager on 2026-11-25 as proposed (not
  an owner ruling; the owner can overrule):* the phrase means a screen that
  reports none at all (potential 1). Any other shows the HDR version fitted,
  labeled **HDR**, even where it looks close to SDR; a display's "current
  headroom" (Terms) is what macOS allows at the moment, not the potential. In
  the PRD: Terms, R5, AC4.

## 18. Design rulings after the early check (2026-11-25)

Both are design judgment, not Apple policy (see the note at the top).

### 18.1 DQ-1: the second change on arrival

**Ruling: option (a), accept it, provided it really happens only rarely.** The
owner accepted it on 2026-11-25: "Yes, Accept it. I did notice it in fact. It's
fine" (RI-6, §17; PRD R6 and AC18). The final manual checks look at it again on
a screen that allows less than the photo needs.

1. While nothing is known about a screen, render for its potential, capped at
   the photo's ceiling. Arrival is not held back. If the settled reading is
   lower, replace the picture once: no animation, spinner or badge change (the
   help tag follows). AC7 counts versions, so this does not count.
2. What was learned is remembered **per screen for as long as the app runs**,
   outside the loupe. It survives going to the grid, a video, comparison and
   review, and moving the window away and back; the single loupe and the
   comparison panes share it. Stage 1 does not do this: the value belongs to
   `LoupeController`, which is discarded when the grid, a video or comparison
   replaces the loupe, and it is reset on a screen move. As built, each return
   from the grid can show the second change again (read from the code, not run).
3. A reading that settles at a request **below** the remembered value says
   nothing about the limit and doesn't erase it. Stage 1 erases it, so a photo
   with a low ceiling would bring the second change back for the next brighter
   one. A reading that shows the screen now allows more does replace it.
4. Only readings taken while the app is active are remembered. The picture
   still follows the others (R6).
5. A remembered value is a starting point. If brightness changed while no HDR
   photo was shown, the next one may be fitted again once. Accepted: nothing can
   be read without asking.

Why not the others: (b) can't know in advance whether the reading will come in
lower, so the first HDR photo on every screen, including one with room to spare,
would arrive about 1.5 s late, and it needs a time limit for an app that is
never given the range. (c) is untested and uses extended range for every
gain-map photo before HDR shows. Should the question ever come back, the
fallback is (b), only for a screen with nothing remembered.

### 18.2 What a screen allows, and what it could

Three numbers differ and the UI must not mix them: the file's headroom, the
screen's **potential** (the most it reports it could ever give) and what it
**allows now** (the settled current reading while the app asks for extended
range, or the remembered one, §18.1).

- The potential answers one question, whether the screen has extended range at
  all (§5, reason 3), and serves as the render value until something is known
  (§18.1). It is never shown and never decides "fitted".
- Wherever this design says the display's current headroom, it means what the
  screen allows now.
- A low value is never a reason for SDR. The badge stays **HDR** with the fitted
  help tag at any value, 1.0× included, whatever the cause: the monitor, its
  brightness or the app being in the background. No new reason, badge, threshold
  or visible mark.
- Why: the picture on screen is the HDR version fitted by the gain map's own
  rule (R6), so **SDR** would be untrue. Any cut-off would be arbitrary, and the
  badge would flip with the brightness keys or a change of app, which §4 and R8
  avoid.
- The help tag says "the display allows %2$@× now", not "can show": the limit
  may be the system's choice at that moment, not the panel's ability.
- Cost, stated plainly: at 1.29× no point is more than about 0.4 stops brighter
  than in SDR, so **Turn On HDR** can look as if it did almost nothing. The help
  tag, VoiceOver and the user guide explain it. The histogram still describes
  the whole HDR version (§7).

## 19. Rulings at design review (2026-11-25)

Design judgment, not Apple policy. Findings are in `review.md`.

### 19.1 SDR badge, choice off, original offline

§4's help tag for **SDR** with the choice off ends by naming **Adjust ▸ Turn On
HDR**, which is dimmed while the original is offline (§2.2, RI-2). For that case
only (the app knows the file has a gain map, RI-3) the help tag is:

> "Showing the cached SDR preview. This file also has an HDR version, which
> needs the original."

The badge and its VoiceOver label are unchanged. A help tag must not send people
to a command they can't use.

### 19.2 The histogram while HDR counts aren't there yet

§7.2 ties the axis to the picture. When the HDR picture is on screen (the single
loupe, or the active comparison pane) and its counts aren't ready, the
inspector draws the HDR frame (line, fill, dashed lines, **HDR** mark) with no
curve, until they arrive. It never draws SDR counts, from the editor or the
thumbnail, under an HDR picture, and VoiceOver gives the label with no
percentage. An empty plot for a moment is honest; the other photo's or the
other version's counts are not. Counts must also be made whenever HDR comes on
screen, however it got there: arrival, **View ▸ Show HDR**, a display move, a
side switch.

### 19.3 Accepted as built

The **HDR** help tag "Showing the HDR version." before the file's headroom is
known (not in §4's table).

### 19.4 HDR returns in place when the original comes back (second review pass)

Accepted as built, and it replaces "on the next opening for offline" in §5's
last-but-one bullet: a photo that is open when its volume is connected again
returns to HDR without being reopened. AC4 asks for HDR "by the next time the
photo is opened", which this meets sooner, and a badge that went on saying
**Offline** or **SDR** for a photo that can be shown would be untrue. A failure
(reason 4) still lasts for the rest of the opening.

One limit is accepted with it. A photo that was **opened** while offline keeps
the Adjust tab's offline state after the volume returns (an older fault,
proposed as its own bug in `status.md`), so its HDR histogram has no counts and
stays an empty frame (§19.2) until the photo is opened again. The empty frame is
right while there are no counts; the cure is that bug's fix, which should check
the histogram too.

### 19.5 Zoom and position when the picture is reloaded (third review pass)

A change in what can be shown should not move the photo: zoom and position stay,
in the loupe and the panes. A soft moment while the sharp rendition loads is
acceptable.

- Accepted as built: the original going offline or coming back, and a screen
  that starts or stops reporting extended range in place.
- **View ▸ Show / Hide HDR** and a move to another display should do the same.
  In the single loupe they still return a photo zoomed to anything but 100% to
  100%. That is older than this feature and happens for every photo, so it is
  left to a follow-up bug (text in `review.md`) and doesn't hold this branch.

### 19.6 DQ-2: the narrowest loupe caption (fourth review pass)

**Ruling: option (a), as built.** The HIG says nothing about this case; this is
judgment. The single loupe takes the first of these that fits whole:

1. Marks centered, badges in full.
2. Marks centered, version badge in its short form.
3. Marks after the position, short form, badges at the trailing edge.
4. The same without the position.

- At every step the version badge and the other badges are whole, and badges
  and position keep at least 8 pt from the marks. Nothing is drawn over
  anything.
- This narrows two earlier rules. Where only steps 3 or 4 fit, the marks are off
  center. Where the width allows one badge set to stay centered and not another,
  a change in the badges moves the marks: **View ▸ Hide HDR**, **Copy**, a map,
  Show Original, the caption spinner, or the next photo. Both happen only in
  narrow captions, mostly near the minimum window with the sidebar and inspector
  shown. Wider captions lay out as before.
- Why: what the badges say (which version is on screen, that this is a copy,
  that it is offline) has to be readable. Centering is a matter of balance and
  is the right thing to give up.
- (b) would keep the marks still by holding them off center at many more widths,
  for every gain-map photo, to prevent a move seen only in a narrow range. (c)
  removes a control and an identity badge and, by the widths in `status.md`,
  still fails with a color label. (d) restricts the window for every view to
  solve one 28 pt row.
- The position is dropped last because the film strip, when shown, marks the
  photo's place, and comparison captions already drop it first (§9).
- Beyond step 4: §20.1, which continues this list and is to be built on this
  branch (it replaces the order first noted here for a follow-up).

### 19.7 The choice when an open photo's original goes offline (fourth review pass)

Accepted as built (QA Q2). The **HDR** check box stays where it is, dimmed,
showing the stored choice; **Adjust ▸ Turn On HDR** is dimmed under that title,
as in every other unavailable case (§2.2). Both return with the volume, without
reopening the photo. A dimmed box is better than one that vanishes: the header
doesn't shift, and the checked state still says what was chosen, while the
version badge and **Offline** say why SDR is shown. What Undo, Redo, a History
revert and **Reset All Adjustments** do then is a requirements question (RI-8 in
`status.md`) and is not decided here.

## 20. Rulings after QA's second pass (2026-11-25)

Design judgment, not Apple policy, apart from the HIG lines quoted. Findings are
Q6 and Q7 in `qa.md` (F12 and F13 in `review.md`). Nothing was built or seen;
every width here is derived by arithmetic from QA's measured loupe widths and is
good to several points at best.

### 20.1 The single loupe's caption never grows (QA Q6)

Two rules, both required. The first keeps the window whole whatever the caption
holds. The second makes sure that what is left in a narrow caption is the right
thing.

#### The guarantee

The caption takes exactly the width it is offered, down to zero, and never
reports its content's width as a minimum. This holds for every combination of
badges, marks and strings, ones added later included. Content that still doesn't
fit is clipped inside the caption, at its **leading** edge.

```swift
.padding(.horizontal, 12)
.frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
.frame(height: Self.height)
.clipped()
```

With both a minimum and a maximum given, a flexible frame "unconditionally adopts
the size proposed for it, clamped to the constraints" (SwiftUI documentation,
`frame(minWidth:idealWidth:maxWidth:…)`). The frame must be outside the padding.
The mechanism is the engineer's; the behavior is not, and it was not built here.
`ViewThatFits` alone can't give it, since it uses its last arrangement whether or
not that fits.

#### The order

The caption takes the first level that fits whole. Each level keeps the changes
of the levels above it. Levels 1 to 4 are §19.6's.

| Level | Change | Where it is still stated |
| --- | --- | --- |
| 1 | Marks centered, badges in full | |
| 2 | Version badge in its short form | Help tag, VoiceOver |
| 3 | Marks after the position, badges trailing, at least 8 pt between them | |
| 4 | Position dropped | Film strip |
| 5 | Film strip button dropped | **View ▸ Show / Hide Film Strip**, ⌥⌘B |
| 6 | Spinner dropped; marks compact (below) | The badge or control that waits |
| 7 | **Copy** dropped | Window title |
| 8 | **Filtered** dropped | Window subtitle, filter toolbar item |
| 9 | **Machine Learning Not Applied** dropped | Noise Reduction group |
| 10 | **Spot Limit** dropped | Spots heading |
| 11 | Color label name truncates at the tail (at least 24 pt); a map badge truncates in the middle (at least 80 pt). Each takes the room left, up to its full width | Help tag |
| 12 | **Original** dropped | **View** menu, `\` |
| 13 | Last: the color label name may shrink to nothing, leaving the dot | Help tag, VoiceOver |

- At levels 3 and up the gap between marks and badges is 8 pt in all. As built it
  is at least 16 (the row's spacing on both sides of an empty spacer).
- **Never dropped, at any level:** the version badge, whole, with its warning
  mark where it has one; the **HDR** badge of an HLG, PQ or DNG photo, whole;
  **Offline**, whole; a map's badge (it may only truncate, from level 11); the
  flag; the rating, in one form or the other; the color dot. This meets R4 and
  AC4: version, warning mark and **SDR**, and **Offline** are always readable,
  and the reason stays in the help tag and VoiceOver label.
- A badge added to this caption later needs its own row in the table.
- Dropping an item takes it off screen only. Nothing about the photo, the filter
  or the strip changes.

**Compact marks.** The five star slots become one `star.fill` in the rating color
followed by the digit (2 pt apart, the digit in the caption's secondary style).
An unrated photo shows no star and reserves no room. Spacing between marks is 6 pt
instead of 10. The VoiceOver label is the one the five stars have, and the help
tag has the same words. Nothing is lost, which is why this comes before any badge
that carries information. It replaces §19.6's earlier "the stars stay".

**The color label name** is one line at every level and never wraps. The label
(dot and name) gets a help tag with the existing "%@ label" words. At level 13 a
sighted person has only the color, against the HIG ("Avoid relying solely on color
to differentiate between objects, indicate interactivity, or communicate essential
information", Color). It is accepted only there: by the estimates it needs a
caption narrower than the loupe is with the side panes at their default widths,
and the help tag and VoiceOver still name the color. No new strings are needed.

#### What this should give

At 240 pt (760 pt window, panes at 220 and 300), by estimate:

- Every photo state without a map goes no further than level 12, with the color
  name whole. Offline, **SDR** warning, **Original**, 5 stars, flag and the
  longest name is the tightest: **Original** goes, and the rest fits with about 10
  points to spare.
- A map badge with "Not Applied" may truncate (level 11).
- Level 13 is not reached.

If a non-map state cuts the color name at 240 pt, or any state reaches level 13
there, report it as a design question instead of changing the order. Below 240 pt
(side panes dragged wider; whether the split view allows it was not checked) the
guarantee holds. The marks begin to be clipped below a caption of about 185 pt,
and the version badge beside **Offline** stays whole down to about 125 pt.

#### Checks

- Keep the level table as plain data in PhotoCore (which items show at each
  level) with a unit test: the never-dropped items are present at every level,
  and each level removes or shrinks only what the table says.
- Debug script, at 760 × 560 with both panes: in every state of `qa.md` T10 and
  T11, and with a filter, a copy, Original, 5 stars, a flag, the longest label
  name and the volume ejected all at once, `print loupe` reports 240 pt, the
  inspector and sidebar buttons are where they are with an unmarked photo, and a
  snapshot shows the version badge and **Offline** whole. Repeat the width check
  with a "Not Applied" map. Printing the level reached helps.

**User guide**, in place of the sentence that begins "In the narrowest windows":

> In the narrowest windows the stars, flag and label move toward the left so that
> no badge covers them. If that isn't enough, the caption leaves things out,
> starting with the position and the **Film Strip** button, and shows the rating
> as one star and a number. **Copy** and **Filtered** can go too (the window's
> title and subtitle still say both). The badge that says which version is on
> screen and the **Offline** badge always stay.

### 20.2 Comparison at narrow widths (QA Q7)

**Split.** The part this branch added is fixed here; the older fault is a
follow-up (text in `review.md`).

- Why not leave it all: the version badges widen each gain-map pane by about
  35 pt (QA, T12), so there are window widths, roughly 1,000 to 1,075 pt for an
  unrated pair, where a gain-map comparison fitted before and no longer does
  (arithmetic from QA's measurements, not measured). That is a regression, with
  HDR off too, since **SDR** always shows.
- Why not fix it all: two panes in 240 pt leave under 100 pt for each caption,
  less than a name, marks and a version badge need on one line. That wants a new
  comparison caption layout, which is older work (#63) and its own design.

**The fix here:** one more arrangement at the end of each pane caption's list,
the same as today's last one but with §20.1's compact marks. Everything else is
unchanged: the name, the version badge, **Copy**, **Offline** and the label name
never drop. Do **not** put §20.1's clamp on the comparison caption: without a drop
order of its own it would cut version badges, which are whole today.

**Check:** `qa.md` T12 at 760 pt. For the gain-map pair, SDR and HDR, each pane is
no wider than on `develop` (235.75 pt); by estimate it becomes much narrower for
unrated photos. Repeat with both photos rated 5 with a flag and a label, against
`develop`. If the pane width doesn't fall, the captions are not what sets it:
leave comparison unchanged and report that, and the whole of Q7 goes to the
follow-up without holding Q6.
