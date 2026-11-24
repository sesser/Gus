# Some HEICs render brighter than Quick Look, and slider edits jump back: design review

Issue: #277. Branch `bug/heic-exposure-bright`. Reviewed 2026-11-24 against
the **Bug** section of `status.md` (with the owner's RI-1 ruling), the existing
design of the loupe's HDR rendition, **HDR** badge and **View ▸ Show / Hide HDR
Highlights**, `docs/USER_GUIDE.md` and the HIG. Read from the sources; nothing
was built or run, so test and debug-script results are the engineer's, from
`status.md`. There is no `design.md` for this fix.

## Verdict

**Pass, with one user guide fix (F1).** The UI is coherent. A gain-map photo
now looks the same at open, while a slider moves, after release, and by the
code's paths at 100% and when comparing, and it matches what previews and
exports hold. The badge and the menu item need no change. F2 is a stale record
to correct before the pull request.

## What the controls do for a gain-map photo

| Control | Behavior now | Judgment |
| --- | --- | --- |
| **HDR** badge (loupe and comparison captions) | Not shown: the badge follows the rendition on screen, and there is no HDR one | Right. The badge says "this is shown with extended range", not "this file holds HDR data" |
| Badge tooltip | Not reachable; unchanged on HDR photos ("Highlights up to N× SDR white are shown with the display's extended range") | Still accurate |
| **View ▸ Show / Hide HDR Highlights** | Stays enabled and its title still flips; choosing it changes nothing on this photo | Right. It is a kept, app-wide view preference (`loupe.showsHDR`), enabled whenever the library window is key, as for any SDR photo before. Dimming it by the focused photo would make a preference look broken or unavailable while stepping through a mixed folder |
| Tooltips elsewhere | None mention gain maps; no string changed | Nothing to change |

No new "SDR" or "gain map" badge is wanted. Most iPhone photos would carry it,
it would report the normal state, and nothing in this build lets a person act on
it. Saying that a photo has an HDR version belongs to the design of #282.

## Requirements

| # | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| D1 | A photo whose HDR comes only from a gain map shows its SDR rendition in the loupe (Bug, Expected) | Pass; look needs manual check (M2) | `decodeHDR` returns nil for a non-raw without HLG or PQ encoding; the loupe keeps the SDR preview |
| D2 | A slider's edit stays on screen after release at the brightness the drag showed | Pass; needs manual check (M2, M3) | No HDR rendition replaces the live frame for any stack; `GainMapRenditionTests` |
| D3 | No **HDR** badge on a gain-map photo | Pass (code, and the engineer's `print hdr`: none) | `display` sets the headroom only for an HDR rendition; the caption draws the badge only with a headroom |
| D4 | Floating-point DNGs and HLG or PQ images keep their HDR rendition, badge and tooltip | Pass (code and tests); needs manual check (M4) | Raw branch unchanged; `hasHDREncoding` decides for non-raws, with or without a gain map |
| D5 | The comparison panes follow the single loupe, each side's badge its own | Pass (code); needs manual check (M7) | Both panes use `PreviewService.hdrImage` and set `comparisonHDRHeadroom` per side |
| D6 | **View ▸ Show / Hide HDR Highlights** keeps its title pair, enabled state and meaning | Pass (code); needs manual check (M6) | `LibraryCommands` unchanged |
| D7 | 100% shows the same rendition as fit | Pass (code); needs manual check (M5) | A nil HDR rendition falls through to `fullResolutionImage` in both views |
| D8 | Grid, film strip, previews and loupe agree for a gain-map photo | Pass (code); needs manual check (M5) | All are SDR now; before, the loupe alone differed |
| D9 | User guide terms match the UI | Pass | **HDR** badge, "caption line" and **View ▸ Hide HDR Highlights** match the app; "floating-point DNG", "HLG or PQ" and "gain map" match the behavior |
| D10 | The user guide's HDR paragraph describes the behavior clearly | **Fail** (F1) | See below |

## Fixes for the engineer

**F1. User guide, "HDR" paragraph: the last three sentences now attach to the
wrong photos.** The new sentences about camera raws and gain-map photos, which
stay SDR, sit between the HDR photos and "The loupe first shows the cached
preview, then the HDR render from the original". That now reads as if the photos
just described get an HDR render, and "**View ▸ Hide HDR Highlights** turns it
off" has lost what "it" is. Keep everything about HDR photos together, then the
SDR ones. Suggested text:

> **HDR**: on a display with extended dynamic range, the loupe shows HDR photos
> with highlights above white: floating-point DNGs (such as Lightroom's HDR
> merges and the app's own DNG merges) and images with HLG or PQ encoding (such
> as some cameras' HDR HEIF files). An **HDR** badge in the caption line under
> the photo says so. The loupe first shows the cached preview, then the HDR
> render from the original, so an HDR photo whose original is offline stays SDR.
> **View ▸ Hide HDR Highlights** turns HDR display off.
>
> Camera raws stay SDR, and so do photos whose HDR comes only from a gain map
> (most iPhone HEIC and JPEG photos, Ultra HDR JPEGs): the loupe shows the same
> standard-range picture that you edit and export, which can look darker than an
> app that shows the gain map's HDR version. Thumbnails and cached previews are
> always SDR.

**F2. `status.md`, README section: "No change" is not right.** `README.md`
(Features) still lists "HDR display of HDR sources (floating-point DNG,
gain-map HEIC and JPEG, HLG and PQ)", which this fix makes false for gain-map
files. Note it there so Ship corrects it (the README is the product manager's at
Ship). The same claim is in `docs/features/_inventory.md` ("HDR display" row,
the product manager's) and in `CLAUDE.md`'s Rendering rule (the owner's; wording
already proposed in `status.md`). Because both README and `CLAUDE.md` change,
step 6 (Ship) applies to this fix.

## Not required on this branch

- **HLG still jumps (RI-2).** By the engineer's synthetic measurements an HLG
  HEIC still moves about 1.5 stops on slider release, and an HLG or PQ file with
  a gain map 1 stop or more. That breaks the same expectation this bug is about:
  what a drag shows is what release leaves (direct manipulation and feedback).
  It is outside the ruling and not changed here. From design, option (a) is
  sound if it is filed as a bug now and checked with a real file; it should not
  wait silently inside #282.
- **The HDR badge leaves during a drag** on HDR photos and stays away for values
  with no HDR rendition (Contrast, Tone Curve and others). This predates the
  fix. #282 should design what editing an HDR photo shows. If the guide should
  say so before then, one sentence is enough: "While you change a setting, and
  with some settings, the loupe shows the photo in SDR without the badge."
- "Gain map" is not defined in the guide. A short gloss (a second image in the
  file that says where an HDR screen should brighten) would help, if wanted.

## What's working

- One rendition for a gain-map photo from thumbnail to export: no brightening
  after the photo appears, and no difference between displays.
- The badge is tied to what is on screen, so it needed no special case.
- HDR merges and HLG or PQ files keep their look and their control.

## Manual checks

For a person at the bundled app on the extended-range display, with a scratch
library holding a copy of the gain-map HEIC and a DNG merge of a scene with
bright highlights. Numbers continue from `status.md`; M1 is done.

- **M2.** Open the gain-map HEIC in the loupe: no brightening after it appears,
  it looks like Quick Look, and the caption has no **HDR** badge. Drag Exposure
  to −1, and Highlights to the left, and let go: the picture stays where the
  drag left it.
- **M3.** Set Contrast to +20, then back to 0: only Contrast's own change, no
  stop-sized drop or return. `\` (Show Original) and hovering a preset show no
  jump beyond the adjustment itself.
- **M4.** The DNG merge still shows bright highlights and the **HDR** badge,
  and its tooltip gives a headroom.
- **M5.** The HEIC at fit, at 100% (Z) and in its grid and film strip
  thumbnails has the same brightness; stepping to it with the arrow keys from a
  neighbor brings no later change.
- **M6.** **View ▸ Hide HDR Highlights**, then **Show**: the item is enabled and
  its title flips on both photos; the HEIC does not change, the merge changes
  and loses and regains its badge.
- **M7.** Select both and press S: the badge appears on the merge's side only,
  and switching the active side (A) changes neither photo's brightness.

If a real HLG HEIF is at hand, dragging a slider on it and letting go would
settle whether RI-2's synthetic result happens with camera files (information
for RI-2, not a condition of this fix).
