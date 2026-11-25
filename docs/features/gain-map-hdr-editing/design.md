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
- Disabled during a crop session, with **Original**.
- Help tag: "Show and edit this photo in HDR, using the brightness
  information in its file. Exports are SDR."
- The header shows only when the editor is ready, as today, so it is absent for
  an offline original (RI-2) and while comparing.

### 2.2 Menu bar

**Adjust** menu, first item after the first separator (above **Auto
Exposure**): **Turn On HDR**, or **Turn Off HDR** when the focused photo's
choice is on.

- Enabled: loupe (review as for the other adjust items), editor ready,
  gain-map photo, not comparing, not cropping. The rule is the one **Adjust ▸
  Black & White ▸** uses, plus "has a choice". Otherwise it stays listed and
  dimmed with the title **Turn On HDR** (HIG, Menus: show unavailable items).
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
- Changing the badge never resizes the photo or moves the culling marks.
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
  never run into the culling marks.
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
  drop last, as today.
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
