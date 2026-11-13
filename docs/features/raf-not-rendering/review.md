# RAF not rendering: design review

Owner: apple-ui-designer. Date: 2026-11-13. Step 4 of `docs/WORKFLOW.md`
(bug fix that changes the UI). Branch `bug/raf-not-rendering` at `4ff5d30`.

Reviewed against: the **Bug** section and the owner's rulings (Q3: "controls
are not hidden unless an adjustment is impossible") in `status.md`;
`docs/features/ui-redesign/design.md` (P5 terms and capitalization);
`docs/features/ml-denoise/design.md` §3 (the rule "hide what can never apply
to this file, dim what could apply on another Mac or after a macOS update",
states S4 and S6) and §6 (the loupe badge); the HIG (Writing; Toggles;
Pop-up buttons). Code read: `Views/AdjustView.swift` (`DevelopControls`,
`fallbackDecoderNote`, `whiteBalance`, the Noise Reduction group),
`Views/AdjustControls.swift` (`AppKitPopUp`, `GroupLabel`, `AdjustText`),
`Model/AdjustmentEditor.swift` (`follow`, `status(for:)`),
`Model/FallbackDecoderText.swift`, `Model/MachineLearningText.swift`,
`Model/AdjustmentActions.swift` (`changeAdjustments`), and
`docs/USER_GUIDE.md` lines 354 to 371. Not built or run by me; the
inspector's look is left to the manual checks (snapshots leave it blank).

## Verdict

The approach is right and I uphold it: a photo LibRaw decodes is adjusted as
a rendered image, the controls that can't reach its render are left out, and
one note in the Profile group's place says why. Three things need fixing
before QA: the machine learning caption and badge tooltip promise a Color
that doesn't apply (F1), the Mode pop-up can show a stale mode after a paste
from a raw macOS decodes (F2), and before macOS 27 the dimmed check box gives
a reason that sends people to a macOS update that won't help (F3). Copy
changes for the note (F4) and the user guide (F5) are small.

## Requirements

| # | Requirement (source) | Result | Notes |
| --- | --- | --- | --- |
| R1 | Such a photo can be adjusted (Q3) | Pass | Tone, Presence, Tone Curve, Color Mixer, Color Grading, masks, Lens, Effects, Sharpening, Luminance and crop all reach the render (`status.md` table) |
| R2 | Controls hidden only where the adjustment is impossible (Q3) | Pass | Profile, Decoder, Kelvin Temperature and Tint, Daylight to Flash and Color noise reduction are hidden; `status.md`'s `photocli` table shows each leaves the render byte-identical |
| R3 | What is missing is explained where people look for it (ml-denoise §3 rule; HIG Writing) | Pass, copy change F4 | The note sits where Profile normally is, under the same heading, so someone hunting for Profile finds the reason |
| R4 | White Balance offers As Shot, Auto, Custom; Temperature and Tint −100 to 100 | Pass (code); M2 | Same rule a JPEG has always had |
| R5 | The Mode pop-up shows the mode that renders | **Fail** (F2) | A pasted Kelvin preset leaves the pop-up on whatever it last showed |
| R6 | Use machine learning dimmed with its reason, not hidden (ml-denoise §3: a camera can gain support) | Pass on macOS 27; **Fail** before (F3) | |
| R7 | Machine learning pasted onto such a photo: caption and badge say what applies instead (ml-denoise S6, §6) | **Fail** (F1) | "Luminance and Color apply instead", but Color doesn't |
| R8 | One term per thing; sentence-style note (ui-redesign P5) | Pass | Heading "Profile" reuses `AdjustText.title(.profile)`; the note is a sentence |
| R9 | No custom chrome; system text styles and secondary label color | Pass | `ControlGroupLabel` and a `.caption` secondary `Text`, as the machine learning and Sharpening Map captions |
| R10 | Strings in the catalog, no brand value | Pass | Key present in `Localizable.xcstrings`; `LocalizationTests` and `BrandingTests` pass per `status.md` |
| R11 | VoiceOver reads heading and note together | Pass (code) | `.accessibilityElement(children: .combine)` |
| R12 | User guide terms match the UI | **Fail** (F5) | "tone curve", "Light", and the dimmed-only machine learning sentence |
| R13 | Note's look: wraps, spacing to White Balance, legible in Increase Contrast | Needs manual check | M1 |

## Rulings on the engineer's Design questions

### D1. The note in Profile's place, or dimmed pop-ups

**Ruling: keep the note, as built.** Do not show the Profile and Decoder
pop-ups dimmed.

- A dimmed Profile pop-up would still show a value ("Standard"), and that
  value is false: there is no profile at all on this decode. A dimmed control
  says "this exists but isn't available right now"; here it doesn't exist.
- A dimmed pop-up explains itself only through a tooltip, which most people
  never see. The note is visible, and it is the one place that also explains
  the White Balance scale and the missing Color row, which are further down
  and would otherwise look like bugs.
- This is consistent with ml-denoise §3 (hide what can't apply to this file),
  with one deliberate difference: unlike a JPEG, this file is a raw, and
  people expect raw controls. A raw that silently loses its Profile group
  looks broken; one that says why does not. That is the reason the note
  exists for these photos and not for JPEGs.
- The heading stays "Profile", without a group check box: there is nothing to
  turn off. It keeps the inspector's rhythm and lands the explanation exactly
  where someone looks for the missing control.

Copy: see F4.

### D2. Kelvin and the named presets (Daylight to Flash) for these photos

**Ruling: not offered, as built.** The relative Temperature and Tint and the
three modes are the only white balance controls a LibRaw photo gets.

- Offering Kelvin or Daylight would put controls on screen that change
  nothing (`status.md`: `temperature=2500` and `preset=daylight` leave the
  render byte-identical). A control that visibly does nothing is worse than
  no control (HIG: controls give feedback; Q3: hide what is impossible).
- Making them work means mapping Kelvin onto LibRaw's as-shot multipliers in
  the renderer. That is new behavior, and two raws of one scene would then
  disagree about what "5500 K" looks like. That is the product manager's
  call, not this fix's: see the proposed follow-up below.
- Kelvin values that arrive by paste, preset or `photocli` stay in the stack
  untouched (they apply again if a later macOS decodes the camera; `status.md`
  R1). The inspector must not misreport them, though: F2.

### D3. The caption when machine learning arrives by paste or preset

A paste or preset carrying machine learning on reaches these photos
(`changeAdjustments` tests `fileKind != .raw`, and these are raws), so they
land in ml-denoise state S6 with the check box on and enabled, which is
right: it must stay possible to turn it off. But S6's caption, the loupe
badge's tooltip and nothing else say "Luminance and Color apply instead" or
"shown with Luminance and Color", and Color is not applied to these photos.

**Ruling:** for a photo the system decoder doesn't read, use these strings
(new catalog keys; the existing ones stay for system raws):

| Where | Text | Comment for the catalog |
| --- | --- | --- |
| Caption and check box help (S6 on such a photo) | Not applied: this camera isn't supported. Luminance applies instead. | Caption and check box help of Use machine learning: the photo asks for machine learning noise reduction, and macOS can't decode this raw file (the app's own decoder has no Color noise reduction); the setting is kept |
| Loupe badge tooltip | This photo is set to use machine learning noise reduction, which doesn't support its camera. It's shown with Luminance instead. | Tooltip of the Machine Learning Not Applied badge, for a raw file macOS can't decode |

The badge title, the triangle, the VoiceOver canvas value and the export's
Activity row ("…their cameras aren't supported.") are right as they are. The
dimmed state (nothing asked) keeps "Not available for this camera."

### D4. A decoder badge in the grid or loupe

**Ruling: no badge.** Not in the grid, not in the loupe caption.

- The caption's badges mark a state that is out of the ordinary *for this
  photo now* and that a person may act on (Offline, Machine Learning Not
  Applied, HDR, Copy). A LibRaw decode is permanent for a whole camera
  (the owner's whole 2019 X-E3 folder), so a badge would sit on hundreds of
  photos forever and train people to ignore badges.
- The moment the difference matters is when editing, and the Adjust tab note
  covers it. The flatter look is explained in the user guide.
- If the owner later wants it visible outside the Adjust tab, the right home
  is a row in the Info tab's file details, not a badge. That is an
  enhancement for the product manager, not part of this fix.

## Fixes for the engineer

**F1 (should fix). Machine learning caption and badge tooltip for these
photos.** Use the two strings in D3 when `usesFallbackDecoder` is true. One
way: carry "the app's decoder" in the status (or pass it to
`MachineLearningText.caption` and `badgeHelp`) rather than adding a new
`Reason`, so the export's Activity rows keep one reason per camera. Add both
keys to `Localizable.xcstrings` with the comments above. Update
`print ml` so QA can read the caption.

**F2 (should fix). The Mode pop-up must show the mode that renders.** When
`balance.preset` is not among the offered items (a pasted Daylight, or
Custom set with Kelvin values on a raw macOS decodes), `AppKitPopUp` finds no
match and leaves the `NSPopUpButton` on its previous item: moving from a
photo showing Custom to a pasted-Daylight X-E3 photo shows Custom; a fresh
view shows As Shot by accident. Show what renders: **As Shot** when both
relative values are 0 (and the preset isn't Auto), otherwise **Custom**. This
is display only; don't rewrite the stack. The same mismatch has always
existed for JPEGs, and the same mapping fixes them; this fix makes it common
because raw-to-raw paste is the usual case. Picking a mode from the pop-up
then behaves as today.

**F3 (should fix). One reason before and after macOS 27.** For a raw the
system decoder gives no image, the dimmed check box currently says "Not
available on this Mac: it needs macOS 27 or later." before macOS 27
(`availability(for:decoderVersions: [])`, C7). That promises an update fixes
it, and nothing says macOS 27 reads this camera (on 27.2 it doesn't).
Machine learning is part of the system decoder, and the system decoder
doesn't read this file on this Mac, so the true reason on every macOS is the
camera. Use `cameraNotSupported` for these photos everywhere (check box,
caption, badge, export row). Judgment, not HIG: the HIG asks for accurate,
actionable messages, and "update macOS" is an action that may do nothing.

**F4 (should fix, copy). The note.** Wanted:

> macOS can't decode this raw file, so it's shown without a profile.
> Temperature and Tint are relative to the camera's white balance, and Color
> noise reduction isn't available.

What changes and why: "it's" as in the app's other captions; "White balance
is relative to the camera's" ends on a dangling possessive and doesn't name
the controls that look different, while "Temperature and Tint" are the
labels the person sees right below. Update the catalog key and the comment
(the comment's facts stay right). Keep the note's place, style and the
combined accessibility element.

**F5 (should fix, user guide). Terms in "Raw files macOS can't decode"**
(`docs/USER_GUIDE.md` 354 to 371):

- "no profile or tone curve" (357): Tone Curve is a group that works on these
  photos. Write "but not the macOS decoder's profile and contrast".
- "Light, Presence, the curve, color, masks, Lens, Effects, Sharpening and
  crop work as usual" (363): Light is the section that holds Profile and White
  Balance, which differ. Write "Tone, Presence, Tone Curve, Color Mixer, Color
  Grading, masks, Lens, Effects, Sharpening and crop work as usual."
- "**Use machine learning** is dimmed" (363): add "unless a paste or preset
  turned it on; it then says it isn't applied, and Luminance applies instead"
  (after F1).
- "a note stands in place of **Profile**" (360): fine; if F4 lands, nothing
  else in the guide quotes the note.

Not this fix's, noted only: line 402, "The Decoder pop-up (Light ▸ Profile)",
is correct (Light is the section heading).

## Improvements (judgment, not required)

- While a photo loads, `isRaw` and `usesFallbackDecoder` are both false, so
  the tab briefly lays out as for a JPEG before switching. If M5 shows a
  visible jump between an X-T3 and an X-E3, hold the previous layout (or the
  loading state) until the file's kind is known. Pre-existing in kind; only
  worth doing if a person sees it.

## What's working

- One test, `SystemRAWDecoder.reads`, behind the editor, Auto White Balance
  and every renderer: the tab can't offer a control the render ignores.
- The note reuses the group heading and the existing caption style; no new
  chrome.
- Auto White Balance on these photos writes relative values and visibly
  changes the photo, so Auto keeps meaning the same thing.
- The pasted Kelvin, Profile and Color values are kept, not stripped, so
  nothing is lost if macOS later reads the camera.

## Manual checks (for a person at the bundled app)

Use a scratch library with one X-E3 RAF (LibRaw) and one X-T3 RAF (macOS).

- **M1. The note's look.** Open the X-E3 photo, Adjust tab. Under "Profile"
  (no check box) the note wraps inside the inspector at its narrowest width,
  in 3 or 4 lines, with clear space before the White Balance heading, and is
  readable with Increase Contrast on (System Settings ▸ Accessibility ▸
  Display). No pop-ups under Profile.
- **M2. White Balance.** Mode lists As Shot, Auto, Custom. Temperature and
  Tint run −100 to 100, start at 0, and dragging them visibly warms and tints
  the photo. Auto changes the photo and sets Mode to Auto; As Shot returns
  both sliders to 0.
- **M3. Machine learning, dimmed.** Details ▸ Noise Reduction shows Use
  machine learning dimmed, "Not available for this camera." under it, the
  same text as its tooltip, and Luminance only (no Color row).
- **M4. Paste from a raw macOS decodes.** On the X-T3, set White Balance to
  Daylight and turn on Use machine learning; Copy Adjustments; paste onto the
  X-E3. Mode shows As Shot (F2), not Daylight or the previous photo's mode;
  the photo's white balance didn't change. Use machine learning is on and
  enabled, with the triangle and "Not applied: this camera isn't supported.
  Luminance applies instead." (F1); the loupe caption shows Machine Learning
  Not Applied, and its tooltip says "…It's shown with Luminance instead."
  Turning the check box off removes both.
- **M5. Switching photos.** Arrow between the X-T3 and the X-E3 in the loupe
  with the Adjust tab open: the Profile group and the note swap, the Kelvin
  and relative sliders swap, and nothing from one photo (a mode, a value)
  shows on the other. Note any visible jump while the X-E3 loads.

## Proposed follow-up (for the main session to file, if the owner wants it)

- **Enhancement: "White balance between raws macOS decodes and raws it
  can't".** Today a Kelvin white balance pasted onto a LibRaw photo, or a
  relative one onto a raw macOS decodes, is kept and does nothing. Decide
  whether paste and presets should translate between the two (relative from
  the as-shot Kelvin, or the reverse), and what happens to a LibRaw photo's
  relative values when a later macOS decodes its camera (`status.md` R1).
  Product manager's call; slug `white-balance-across-decoders`.

## Summary for the issue

Design review: **changes requested** (3 should-fix, 2 copy). Approach upheld:
a raw macOS can't decode is adjusted as a rendered image, with a note under
"Profile" in place of the group.
Rulings: D1 keep the note (no dimmed pop-ups); D2 no Kelvin or Daylight to
Flash for these photos; D3 their machine learning caption and badge drop
"Color" ("Luminance applies instead"); D4 no decoder badge.
Fixes: F1 the D3 strings; F2 the Mode pop-up shows As Shot or Custom when a
pasted preset isn't offered (it showed a stale mode); F3 the camera reason
on every macOS, not "needs macOS 27"; F4 note copy; F5 user guide terms.
Manual checks M1 to M5. Proposed follow-up: white balance across decoders.
Full review: `docs/features/raf-not-rendering/review.md`
