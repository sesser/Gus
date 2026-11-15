# White balance and baseline look across decoders: design

Owner: apple-ui-designer. Date: 2026-11-14. Issue #170 (covers #171). PRD: the
issue body, approved by the owner 2026-11-14. Branch
`feature/libraw-color-pipeline`.

Read for this design: the PRD (R1 to R14, AC1 to AC14, open item O8);
`docs/features/raf-not-rendering/review.md` (rulings D1 to D5) and
`status.md`; `docs/features/ui-redesign/design.md` (P5, terms and
capitalization); `docs/features/ml-denoise/design.md` §3 (hide what can never
apply to this file, dim what could apply elsewhere; states S4 and S6);
`Sources/PhotoApp/Views/AdjustView.swift` (`DevelopControls`,
`fallbackDecoderNote`, `whiteBalance`, `pick`),
`Views/AdjustControls.swift` (`AdjustSlider`, `AppKitPopUp`, `GroupLabel`,
`GroupToggle`), `Model/FallbackDecoderText.swift`,
`PhotoCore/Edits/Adjustments.swift` (`WhiteBalance`, `relativeDisplayPreset`,
`raw(_:)`), the String Catalog, and `docs/USER_GUIDE.md` 354 to 379. HIG
areas: Writing, Pop-up buttons, Sliders, Accessibility, Color.

Terms below: a **system raw** is a raw the macOS decoder reads
(`SystemRAWDecoder.reads`, the X-T3); a **LibRaw photo** is a raw it gives no
image for, decoded by LibRaw (the X-E3); a **rendered image** is a JPEG,
HEIC, TIFF or PNG.

## 1. The decision in one paragraph

A LibRaw photo's White Balance group becomes the system raw's group, control
for control: the nine modes, Temperature in Kelvin, Tint. Nothing in that
group tells the person which decoder is in use, because nothing there behaves
differently any more (that is the point of R1 and R9). The Profile heading
keeps its note (ruling D1 stands), reworded: it no longer mentions relative
Temperature and Tint, and it no longer says "without a profile", which R6
and R8 make untrue. Stored relative values on any raw are shown as As Shot.
When a LibRaw photo has no usable color data (R14), the group says so in a
caption under a dimmed Mode pop-up instead of offering sliders that would
do nothing. Rendered images are unchanged.

## 2. What each kind of photo shows

| | System raw | LibRaw photo | LibRaw photo, white balance unavailable (§6) | Rendered image |
|---|---|---|---|---|
| Profile heading | Profile and Decoder pop-ups (unchanged) | The note (§3), no pop-ups | The note (§3) | Absent (unchanged) |
| White Balance modes | Nine (unchanged) | **Nine** (was three) | Mode dimmed on As Shot (§6) | As Shot, Auto, Custom (unchanged) |
| Temperature | Kelvin, reciprocal scale (unchanged) | **Kelvin, reciprocal scale** (was −100 to 100) | Not shown | −100 to 100 (unchanged) |
| Tint | −150 to 150 (unchanged) | **−150 to 150** (was −100 to 100) | Not shown | −100 to 100 (unchanged) |
| Slider default (fill origin, double-click reset) | Decoder's as-shot value | **As-shot value from the color step (R4)** | n/a | 0 |
| Auto | Stores Kelvin and tint | **Stores Kelvin and tint** (AC3) | Not offered | Stores relative values (unchanged) |
| Mode shown | §5 rule for raws (new) | §5 rule for raws | §6 | D5 rule (unchanged) |
| Color noise reduction, Use machine learning | Unchanged | Unchanged (no Color row; ML dimmed, D3 copy) | Unchanged | Unchanged |

Rendered images change in nothing, on screen or in the render (R9, R11).

## 3. The Profile heading's note

**Ruling D1 stands: keep the note under a "Profile" heading with no check
box, no pop-ups.** The PRD's non-goals exclude a Profile pop-up for LibRaw
photos, and a dimmed pop-up would have to show a value; the one value there
is ("built-in") isn't one of Standard, Neutral or Flat, so it would invite a
question the note answers better. The heading still lands the explanation
where someone looks for the missing Profile and Decoder pop-ups.

What has to change: the current copy says the photo is "shown without a
profile" (R6 and R8 give it a built-in profile and a baseline look) and that
"Temperature and Tint are relative to the camera's white balance" (no longer
true). New copy, wanted exactly:

> macOS can't decode this raw file, so it's shown with a built-in profile
> that can't be changed. Color noise reduction isn't available.

Why this wording:

- The first sentence keeps the cause ("macOS can't decode this raw file")
  because it is the only place in the app that says why this photo lacks
  controls other raws have, and D4 rules out a decoder badge. It doesn't name
  LibRaw or the app: the person needs to know what they can't do, not which
  library does the work. No product name, so no `%@`.
- "a built-in profile that can't be changed" says exactly why there is no
  Profile pop-up, without claiming the photo has no profile.
- White balance is not mentioned: it now works as on every raw, and a
  sentence about it would suggest a difference that no longer exists.
- Color noise reduction is still not available (PRD non-goal), and its row
  is missing further down, so it stays in the note.
- Sentence-style, contractions as in the app's other captions (P5).

Place, style and accessibility unchanged: 11 pt (`.caption`) secondary text,
wrapping, under `ControlGroupLabel(AdjustText.title(.profile))`, the heading
and note one combined accessibility element. Replace the catalog key (remove
the old one; `LocalizationTests` must keep passing) and update
`FallbackDecoderText.note`.

## 4. The White Balance group for a LibRaw photo

Exactly the system raw's group (HIG, Consistency: the same control means the
same thing on every raw; this reverses D2, as R2 requires).

```
White Balance                                         [✓]
Mode         [ Daylight            ⌄ ]
Temperature  ───────●──────────────────  [ 5,500 K ]
Tint         ──────────●───────────────  [     +10 ]
```

- **Mode.** The nine items in the system raw's order: As Shot, Auto,
  Daylight, Cloudy, Shade, Tungsten, Fluorescent, Flash, Custom. Same titles
  and catalog keys as today. Each named mode sets the same Kelvin and tint as
  on a system raw (`WhiteBalance.raw(_:)`): Tungsten shows 2,850 K, tint 0
  (AC1). Dimmed while Auto measures, as today.
- **Temperature.** The existing Kelvin slider (`.kelvin` format,
  `.reciprocal` scale, `WhiteBalance.temperatureRange`). Its value for an
  unedited photo, its fill origin and its double-click reset are the as-shot
  Kelvin computed by the color step (R4). That number must be believable
  (R4, R5); if the color step can't produce one, the photo is in the
  unavailable state (§6), never showing 5,500 K as a stand-in.
- **Tint.** The existing tint slider (`WhiteBalance.tintRange`), its default
  the as-shot tint.
- **Changing either slider** sets Custom, one undo step per gesture, undo
  names "Temperature" and "Tint", exactly as on a system raw.
- **Auto** measures and stores a Kelvin and tint (AC3); Mode then shows
  Auto and the sliders show the values. The pop-up is dimmed while
  measuring, as today. LibRaw decodes are slower (about 0.6 s half size for
  an X-E3), so this dimmed moment is longer; no other feedback is added
  unless M3 finds it too long to read as "working" (then return a Design
  question; don't add a spinner on your own).
- **Live feedback.** Dragging Temperature or Tint on a LibRaw photo must
  update the loupe while the slider moves, as on a system raw (HIG: controls
  show their effect). The color step runs after the decode (R3), so a drag
  should not need a new decode; if it does at some zoom, the engineer
  reports it in `status.md` and M8 checks it.

The group heading, its check box, the Develop section's reset and Reset All
behave as for every group. Nothing in the group names the decoder (§7).

## 5. The mode shown on a raw (both decoders)

R10 makes stored relative values inert on every raw, and AC10 says such a
photo shows As Shot. Today a system raw's pop-up shows the stored `preset`
as is, which is wrong for those stacks (a relative Custom would show Custom
with as-shot sliders and an as-shot render). One rule now serves both kinds
of raw. Mode shows:

1. **The stored mode** when the white balance holds Kelvin values
   (`temperature` or `tint` set), or the stored mode is a named light source
   (Daylight to Flash). This is every mode written on a raw by this build.
2. **Custom** when the stored mode is Custom with no Kelvin values and both
   relative values are 0: the person chose Custom from the pop-up, and it
   must stick (D5's reasoning: a pop-up that refuses the item just chosen
   looks broken). It renders as shot, as choosing Custom on a raw always has.
3. **As Shot** otherwise: As Shot itself, an Auto with no Kelvin values
   (a relative Auto from a rendered image or a #161 build), or a Custom
   carrying relative values. These render as shot, so the pop-up says so.

Display only: the stack is never rewritten (R9, R10). The sliders show the
as-shot values whenever Kelvin values are absent, which agrees with rule 3.
Picking a mode from the pop-up then behaves as today: As Shot clears the
white balance, a named mode stores its Kelvin and tint, Custom stores Custom
(on a raw, with the Kelvin and tint it shows: ruling §17.1).

Rendered images keep D5's rule (`relativeDisplayPreset`) unchanged.

Engineer: put the raw rule beside `relativeDisplayPreset` in PhotoCore (a
`kelvinDisplayPreset`, say) and test the cases: stored Tungsten shows
Tungsten; Custom with Kelvin shows Custom; Custom at 0/0 with no Kelvin
shows Custom; Custom with relative 60/30 shows As Shot (AC10); relative Auto
shows As Shot; As Shot shows As Shot.

## 6. White balance unavailable (R14)

A LibRaw photo whose camera has no matrix in LibRaw, or whose file has no
usable white balance coefficients, renders as shot at the baseline (R14).
The Adjust tab must not offer sliders that change nothing (the reason D2 hid
them in #161), and must not go silent either.

Following ml-denoise §3's rule (dim what could apply after an update: a
later LibRaw or macOS may know the camera), the group stays, with its
controls reduced to what is true:

**W1. Nothing asked** (Mode by §5 would be As Shot):

```
White Balance
Mode         [ As Shot             ⌄ ]   ← dimmed
             Not available for this photo: its color data
             can't be read.
```

- Mode: a dimmed pop-up showing As Shot. Its help tag is the caption.
- Caption: 11 pt `secondaryLabelColor`, wrapping, aligned with the pop-up's
  leading edge (under the control it explains, as the machine learning
  caption sits under its check box), 2 pt below it.
- Temperature and Tint: not shown. A dimmed slider must still show a
  number, and there is no Kelvin to show; a made-up one would be false (the
  same reasoning as D1).

**W2. Something asked but not applied** (Mode by §5 would be anything other
than As Shot: a white balance pasted, applied from a preset or set by
`photocli`). The person must be able to see it and remove it (ml-denoise S6:
only the person removes a setting):

```
White Balance                                         [✓]
Mode         [ Daylight            ⌄ ]   ← enabled: As Shot, Daylight
             ⚠ Not applied: this photo's color data can't be
               read. It's shown as shot.
```

- Mode: enabled, with two items: As Shot and the stored mode, the stored
  mode selected. Choosing As Shot clears the white balance (one undo step,
  "White Balance") and the group moves to W1. Choosing the stored mode does
  nothing. The full nine are not offered: each would change nothing on
  screen.
- Caption: the orange `exclamationmark.triangle` then the text, the same
  "not applied" look as the machine learning caption and the missing
  look-up table (one look, one meaning; P5). Its help tag is the caption.
- The group check box shows, because the group is modified, and works as
  everywhere (it changes nothing on screen here, as with any not-applied
  setting).

Both states need the editor to know the photo is unavailable when it lays
out the tab, as it knows `isRaw`; the tab already shows its spinner until
the file's kind is known, so no layout of the wrong kind is drawn. If
availability can only be learned from a decode that comes later, the
engineer returns a Design question before building a layout that switches
under the person.

Auto White Balance for such a photo (from a batch command) stores nothing
for it, or stores what it stores for a system raw it can't measure; either
way §5 and W1/W2 show the result honestly. The engineer records which.

## 7. Decoder visibility (O8)

**D4 stands: no decoder badge** in the grid, loupe caption or White Balance
group. The White Balance group now behaves the same on both decoders, so
there is nothing there for a person to act on. The Profile note (§3) is the
one place the difference shows, which is where controls actually differ.
The single-illuminant accuracy limit (R3) and the baseline look's closeness
to Apple's (R6) are documented in the user guide, not in the inspector: they
don't change what a person can do.

## 8. What does not change

- System raws: every control, value, mode list and string, except that §5's
  rule now also shows As Shot for a relative white balance pasted from a
  rendered image (today it shows Custom or Auto while rendering as shot),
  and Custom picked from Mode stores the numbers it shows (§17.1).
- Rendered images: the three modes, relative sliders and D5's rule.
- The machine learning check box, caption and badge for LibRaw photos (D3,
  F3), and the missing Color row.
- Paste, presets and batch commands: no new UI. Undo names unchanged.
- No new menu items, toolbar items or shortcuts.

## 9. Accessibility and Increase Contrast

- All controls are the existing system-backed ones (`NSPopUpButton`,
  `NSSlider` with its field); their labels ("Mode", "Temperature", "Tint")
  and value formats ("5,500 K") are unchanged, so a LibRaw photo reads
  exactly like a system raw.
- The note stays one combined element (heading + text).
- W1 and W2: the caption is static text after the pop-up in reading order,
  and is also the pop-up's help (so a dimmed pop-up explains itself). The
  triangle is decorative to accessibility; the text says "Not applied", so
  nothing is carried by color or symbol alone.
- Increase Contrast: secondary label color, the disabled control colors and
  system orange all have high-contrast variants; nothing new is drawn. The
  library window is dark only; check the caption there (M7).
- Keyboard: the Mode pop-up and sliders keep their focus order; in W1 the
  dimmed pop-up is skipped by full keyboard access as any disabled control.

## 10. Strings

| Key (English value) | Status | Comment for the catalog |
|---|---|---|
| macOS can't decode this raw file, so it's shown with a built-in profile that can't be changed. Color noise reduction isn't available. | **Replaces** the current note key | Adjust tab, under the Profile heading, for a raw file the macOS raw decoder cannot read: the app decodes it itself with one built-in profile (no Profile or Decoder choice) and has no Color noise reduction. White balance works as for other raws |
| Not available for this photo: its color data can't be read. | New | Adjust tab, under the dimmed White Balance Mode pop-up and as its tooltip: a raw file macOS can't decode whose camera color data (matrix or white balance) the app's decoder can't use; white balance can't be changed |
| Not applied: this photo's color data can't be read. It's shown as shot. | New | Adjust tab, after a warning symbol under the White Balance Mode pop-up and as its tooltip: the photo holds a white balance (pasted or from a preset) that can't be applied because its camera color data can't be used; the setting is kept |

No product name in any of them. Mode titles, slider labels and undo names
reuse existing keys. Remove the old note key from the catalog.

## 11. Custom chrome

None. Everything is an existing control or caption style. The one
composition that is new, a caption under a pop-up, reuses the machine
learning caption's text style and triangle.

## 12. Notes for the engineer

- The view's `editor.isRaw` currently decides both the Profile group and the
  Kelvin controls. Split them: Profile, Decoder and Color noise reduction stay
  on `isRaw` (system raw); the Kelvin White Balance group goes on "raw by
  either decoder, white balance available"; §6 on "LibRaw photo, white
  balance unavailable". Names are yours.
- `rawDefaults?.temperature` and `tint` (or their LibRaw equivalent) must
  give the as-shot values for a LibRaw photo before the tab lays out.
- Extend the debug script's `print ml` to print the White Balance state
  (`wb state kelvin|unavailable|unapplied`), the caption, and the note, so QA
  can script AC1, AC3, AC10 and AC14 against the strings in §10.
- `docs/USER_GUIDE.md` 354 to 379, "Raw files macOS can't decode": replace
  "has the camera's white balance but not the macOS decoder's profile and
  contrast, so it starts out flatter and darker" with what is true after R6
  (a built-in profile and baseline look close to, not identical with, a raw
  macOS decodes); replace "White Balance offers As Shot, Auto and Custom,
  with Temperature and Tint relative … (no Kelvin scale and no Daylight to
  Flash)" with "White Balance works as on any raw: the same modes, Kelvin
  and Tint" plus the accuracy limit for files with one color matrix (R3) and
  the unavailable case (§6); drop "keep their Kelvin white balance … which do
  nothing here" for white balance (Profile and Color noise reduction still
  do nothing); replace "a Temperature or Tint set meanwhile no longer
  applies" with "their white balance still applies". Use the UI's terms:
  **White Balance**, **Mode**, **As Shot**, **Temperature**, **Tint**,
  **Profile**.

## 13. Design review checklist (for step 4)

| # | Check | Source |
|---|---|---|
| DR1 | LibRaw photo: nine modes, Kelvin Temperature, Tint −150 to 150; Tungsten shows 2,850 K / 0 | §4, AC1 |
| DR2 | As-shot Kelvin and tint shown unedited, believable; double-click resets to them | §4, R4 |
| DR3 | Auto stores and shows Kelvin and tint | §4, AC3 |
| DR4 | §5 rule on both raw kinds; Custom sticks; relative values show As Shot | §5, AC10 |
| DR5 | Rendered images unchanged (three modes, relative sliders, D5) | §8 |
| DR6 | Note copy exactly §3; old key gone | §3, §10 |
| DR7 | W1 and W2 as drawn; no sliders; captions and help exact | §6, AC14 |
| DR8 | No decoder badge or group wording naming the decoder | §7 |
| DR9 | User guide terms match the UI | §12 |

## 14. Manual checks (for a person at the bundled app)

Scratch library with one X-E3 RAF (LibRaw), one X-T3 RAF (macOS) and one
JPEG. None of these needs VoiceOver or another macOS.

- **M1. The note.** X-E3, Adjust tab: under "Profile" the §3 text wraps
  cleanly at the inspector's narrowest width, with clear space before White
  Balance. No pop-ups under Profile.
- **M2. White Balance on the X-E3.** Mode lists the nine modes. Unedited,
  Temperature shows a plausible Kelvin (near the X-T3's for a similar
  scene). Tungsten turns the photo clearly blue and shows 2,850 K, tint 0;
  Shade warms it. Double-clicking Temperature returns it to the as-shot
  value.
- **M3. Auto on the X-E3.** Choose Auto: the pop-up dims briefly, then shows
  Auto with a Kelvin and tint, and the photo looks neutral. Note whether the
  wait reads as "working" or as a hang.
- **M4. Paste both ways.** On the X-T3 set Daylight, Copy Adjustments, paste
  onto the X-E3: Mode shows Daylight and the photo changes. Set 4,000 K on
  the X-E3 and paste onto the X-T3: it changes too. ⌘Z undoes each paste in
  one step.
- **M5. Switching photos.** Arrow X-T3 → X-E3 → JPEG → X-E3 with the Adjust
  tab open: the raws show the same group; only the JPEG shows three modes
  and −100 to 100. No mode or value from one photo shows on another; no
  visible jump while the X-E3 loads.
- **M6. A photo edited with a #161 build** (relative Temperature or Tint on
  an X-E3; the owner's library has a few): Mode shows As Shot, the sliders
  show as-shot values, the photo looks as shot. Choose Custom from Mode: it
  stays Custom, Temperature and Tint stay on the same as-shot numbers (no
  fill from the slider's origin) and the photo does not visibly change
  (§17.1); ⌘Z returns to As Shot in one step. Repeat on the X-T3 with no
  earlier edit: the same.
- **M7. Unavailable state** (only if a file that triggers it is at hand; QA
  can script the strings with the synthetic file of AC14): the dimmed pop-up,
  the caption's wrap and legibility in the dark window with Increase Contrast
  on; after a paste, the triangle caption and the two-item pop-up; As Shot
  removes it.
- **M8. Live drag.** Drag Temperature on the X-E3 at fit and at 100%: the
  loupe follows the slider while it moves, not only on release.

## 15. Requirements issues (for the product manager)

- **RI-W1. Relative values left behind on a raw.** R10 keeps a #161 build's
  relative values in the stack, inert on raws. When the owner then sets a
  Kelvin on such a photo, the relative values stay with it; copying that
  photo's adjustments and pasting onto a JPEG applies them to the JPEG
  (warming it by +60, say), which the person never set on anything they can
  see. Options: (a) accept (owner only, a few photos; the JPEG's own sliders
  show the values, so it is visible and undoable); (b) a person's own change
  to White Balance on a raw (a slider, a mode) also clears the relative
  values, as part of that one undo step: not an automatic migration, but it
  does rewrite part of the stack R10 says stays. Recommendation: (a), given
  the number of photos involved; (b) if the count before Ship (O5) is large.
  The design works either way.

## 16. Design questions

None open. §4 (Auto's wait) and §6 (when availability is known) name the two
points where the engineer returns a Design question instead of deciding.

## 17. Rulings

### 17.1 DQ-1: choosing Custom on a raw (2026-11-14)

**Ruling: option (b), on every raw by either decoder.** Choosing **Custom**
from Mode on a raw stores Custom *with the Kelvin and tint the sliders show*,
so §5 rule 1 shows Custom and what is stored is what the person sees.

Why: Custom means "these numbers". The sliders already show numbers when
Custom is picked (the as-shot ones); storing them makes the pop-up, the
sliders, the render and a later paste agree. Auto already stores numbers
(AC3), so Custom now behaves like its neighbor. Option (a) leaves a pop-up
that refuses the item just chosen, which D5 ruled looks broken; (c) is
RI-W1(b), not taken.

The rule, exactly (`WhiteBalanceControls.picking(.custom, from:)` for
`.kelvin(asShot:)`):

1. Start from the stored white balance; set `preset` to `.custom`.
2. If `temperature` is nil, set it to `asShot.kelvin`; if `tint` is nil, set
   it to `asShot.tint`. A value already stored is kept (a Tungsten turned
   into Custom keeps 2,850 K and 0; a `photocli` Kelvin without a tint gets
   the as-shot tint, as the sliders do).
3. Store the as-shot values exactly as `asShot` holds them, **unrounded**, so
   each slider sits on its default (no fill, double-click changes nothing)
   and the field reads the same number as before the pick.
4. Leave `relativeTemperature` and `relativeTint` as stored (R10, RI-W1(a)).
5. One undo step, named "White Balance" (unchanged). If the result equals
   the stored value (Custom already holding both numbers), nothing is
   recorded (`change` already skips equal values).

Unchanged: rendered images (`.relative`) store Custom alone, as D5 says;
an unavailable photo (`.unavailable`) returns nil, as §6 says; §5's display
rule is unchanged (rule 2 still shows Custom for a stack stored without
numbers by an earlier build).

Consequences, accepted:

- §8's "system raws unchanged" gains one exception: Custom picked on a
  system raw now carries its as-shot numbers. Pasting that Custom onto
  another raw applies those numbers (WYSIWYG), where before it left the
  target as shot. The render of the photo itself may differ from as shot by
  the decoder's rounding only; nothing visible.
- The stack hash changes when Custom is picked, so a new preview is made for
  that photo. Expected for any edit.

Tests: replace the `leftover` expectation in
`WhiteBalanceAcrossDecodersTests` (Custom on 60/30 now gives Custom with the
as-shot Kelvin and tint and the relative values kept, shown Custom), and add:
Custom from As Shot on a `.kelvin` photo stores as-shot Kelvin and tint;
Custom from Tungsten keeps 2,850 / 0; Custom with only `temperature` set
fills the tint; `.relative` still stores `WhiteBalance(preset: .custom)`;
`.unavailable` still returns nil. M6 is updated to match.

**Amendment (2026-11-14, second review pass): the as-shot clamp.** On a
LibRaw photo, "as-shot" in steps 2 and 3 means
`CameraColorStep.rendered(asShot)`: the camera's white clamped to
`WhiteBalance.temperatureRange` and `tintRange`. The sliders show that
number, Custom stores it and it renders; As Shot itself still renders the
camera's own neutral. For light beyond the ranges (under 2,000 K, a tint past
±150) the photo therefore shifts the first time Custom or a slider is used.
Accepted: one number shown, stored and rendered keeps the controls and a
paste in agreement, a range that differs per photo would be worse, and As
Shot is the way back. Manual check M10 in `review.md`.
