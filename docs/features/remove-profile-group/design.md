# Remove the Profile group: design

Owner: apple-ui-designer. Date: 2026-11-18. Issue #219. PRD: the issue body,
approved by the owner 2026-11-18. Branch `feature/remove-profile-group`.

Read for this design: the PRD (R1 to R12, AC1 to AC11, the designer's open
questions); `docs/WORKFLOW.md`; `CLAUDE.md`; `docs/UI_REDESIGN.md` (the Adjust
tab's order, "Light (was Develop)"); `docs/features/ui-redesign/design.md`;
`docs/features/ml-denoise/design.md` (§3, §4, §9);
`docs/features/white-balance-across-decoders/design.md` (§3, ruling D1 of
`raf-not-rendering/review.md`); `Sources/PhotoApp/Views/AdjustView.swift`
(`DevelopControls`, `profile`, `decoderPopUp`, `fallbackDecoderNote`,
`machineLearningRow`), `AdjustControls.swift` (`AdjustSection`,
`SectionToggle`, `GroupLabel`, `AdjustText`), `Model/FallbackDecoderText.swift`,
`Model/MachineLearningText.swift`, `Model/PresetActions.swift` (`PresetText`),
`Presets/CameraRawMapping.swift`, `Edits/Adjustments.swift` (`Section`,
`Group`, `presetGroups`, `isDefault`, `effective`), the String Catalog and
`docs/USER_GUIDE.md`. HIG areas: Pop-up buttons, Inspectors, Writing,
Accessibility, Consistency.

Terms: the Adjust tab's first heading is called **Light** in the UI (the
group of that name is the code's `develop` section, and the PRD calls it the
Develop heading). Its groups, top to bottom: White Balance, **Tone** (the
`light` group, with Auto), Presence. A **system raw** is a raw the macOS
decoder reads; a **LibRaw photo** is a raw it gives no image for; a
**rendered image** is a JPEG, HEIC, TIFF or PNG.

## 1. The decision in one paragraph

Delete the Profile group and everything that existed only to explain or
duplicate it: the Look pop-up, the Decoder pop-up, the LibRaw photo's note and
its undo name. Nothing replaces them. Light then starts at White Balance for
every kind of photo, which is exactly how it already looks for a rendered
image, so no new layout, metric or component is needed. **Use machine
learning** stays where it is, untouched. A stored Look is neither shown nor
mentioned: the value is a record, not a control, and a disabled or "not
applied" Profile row would put back the group the owner removed (non-goals).
This is the smallest UI change the PRD allows (HIG, Consistency: one tab layout
for every photo; Hierarchy: no control whose only job is to say it does
nothing).

## 2. Light without Profile

Before, for a raw: `Light` heading, then `Profile` label with its pop-ups, then
White Balance, Tone, Presence. For a LibRaw photo the Profile label carried a
caption instead. After, for every kind of photo:

```
Light                                              [✓] [↺]
White Balance                                      [✓]
Mode         [ As Shot             ⌄ ]
Temperature  ───────●──────────────────  [ 5,500 K ]
Tint         ──────────●───────────────  [     +10 ]
Tone                                [Auto]         [✓]
Exposure     ...
Presence                                           [✓]
Clarity      ...
```

- **The code.** `DevelopControls.body` loses its `if editor.isRaw { … } else if
  editor.usesFallbackDecoder { … }` block: the `VStack` starts with
  `GroupLabel(.whiteBalance, editor: editor)`. `profile`, `decoderPopUp`,
  `lookTitle` and `fallbackDecoderNote` are deleted. Nothing else in the file
  changes.
- **Spacing.** `GroupLabel` already carries its own top padding
  (`InspectorMetrics.groupLabelTop`), and a rendered image's Light already
  starts with White Balance, so the first group sits under the heading exactly as
  it does for a JPEG today. No spacing change, no `showsTurnedOff` change.
- **Heading state.** `Adjustments.Section.develop.groups` becomes
  `[.whiteBalance, .light, .presence]`. `AdjustSection` and `SectionToggle`
  already compute everything from `section.groups`, so with no code of their own:
  - the heading's check box is checked when every modified group among those
    three is on, mixed when only some are, unchecked when none is, and is
    shown only while one of them is modified (as today);
  - the reset arrow is enabled only while one of the three is modified, and
    its help is still "Reset Light";
  - Reset Light and Turn Off / Turn On Light no longer touch the `rawDecode`
    operation (they never will again: no group owns it).
  So a photo whose only edit is a stored Look or a stored decoder version has an
  unmodified Light heading (no check box, reset dimmed). That is correct: nothing
  in the heading can be changed or reset.
- **Heading's name.** Light stays. Its catalog comment ("profile, white balance,
  tone, presence") is updated to "white balance, tone, presence".
- **Expanded/collapsed state** is stored per section, not per group
  (`adjust.section.develop`): unaffected.

`Adjustments.Group.profile` is removed from `Group` and from
`Section.develop` (the PRD's R6); `AdjustText.title(_ group:)` loses its
`.profile` case, so a missing case fails the build instead of leaving a dead
string.

## 3. Use machine learning (Noise Reduction group)

**No change to where it sits or how it looks.** The check box stays the first
row of the Noise Reduction group under the Details heading, above Luminance
and Color, with the caption below it (ml-denoise design §3). It is already the
primary control for machine learning, and the Decoder pop-up was only "a second
view of the same state" (ml-denoise §4); with the second view gone there is one
view, so nothing is lost and nothing needs to move.

What follows from the Decoder pop-up leaving:

| Item | Ruling |
|---|---|
| Check box states S1 to S8, their captions, tooltips, the Color row's dimming, the loupe badge, the VoiceOver canvas value, the Activity rows | Unchanged. None of the strings names Profile or Decoder, except the one below |
| "Turn off Use machine learning to choose another decoder." (`MachineLearningText.decoderDimmedHelp`) | Delete the string, its use and its catalog entry. Its only host was the dimmed Decoder pop-up |
| `MachineLearningText.decoderItem` ("%@ (machine learning)") | Delete with its catalog entry. Its only host was the pop-up's item |
| `"%@ (default)"` (the pop-up's default item, `comment: "RAW decoder version"`) | Delete with the pop-up |
| `MachineLearningText.caption/checkBoxHelp/badgeHelp(fallbackDecoder:)` | **Keep.** The parameter is about the missing Color row on a LibRaw photo, not about the Profile group, and the "Luminance applies instead" wording is now the only place that says Color isn't used there |
| `MachineLearningNoiseReduction.Status.decoderChoiceIsEnabled` | No UI left; the engineer removes it with the pop-up |
| Undo name | Selecting or deselecting Use machine learning is "one undo step" today, named for the control; unchanged. The pop-up's undo name "Decoder" disappears with it |
| Description of the setting where it appears on a LibRaw photo | Unchanged: the check box is shown, dimmed, with "Not available for this camera." (S4) |

The engineer decides what survives of `editor.chooseDecoder`,
`RawDefaults.offeredDecoderVersions` and `defaultDecoderVersion`; that is not a
UI question. The only UI rule: no control may set a decoder version other than
through Use machine learning (PRD non-goal "no new decoder versions or
controls").

## 4. The LibRaw photo's note (`fallbackDecoderNote`)

**Delete it** (PRD R1). This supersedes ruling D1 of
`raf-not-rendering/review.md` and §3 of the white-balance-across-decoders
design, which kept the note "where someone looks for the missing Profile and
Decoder pop-ups". With no Profile heading nobody looks there.

What the note used to say, and where each half now stands:

- "macOS can't decode this raw file, so it's shown with a built-in profile that
  can't be changed." The second half has no referent any more. The first half
  was the only text in the app saying why a LibRaw photo lacks controls other
  raws have. The remaining differences are small and each explains itself where
  it appears: Use machine learning is dimmed with "Not available for this
  camera." (S4), a pasted machine learning setting says "Luminance applies
  instead" (S6, `fallbackDecoder: true`), and White Balance is the same
  group as on any raw (design D2 was reversed in #170).
- "Color noise reduction isn't available." The Color row is simply absent
  (`editor.isRaw` is false), which is the HIG's rule for a control that can
  never apply to this file: hide it, do not dim it.

I do not recommend a replacement caption under Luminance. It would add a note
to explain an absence, in the group the PRD says does not change, and the
owner has asked for the note to go. If testers later report confusion, the
place to add it is a one-line caption under Luminance, as a new issue.

Delete: `FallbackDecoderText.note` (and the `FallbackDecoderText` enum; keep
`WhiteBalanceText` in the file), its catalog entry ("macOS can't decode this
raw file, so it's shown with a built-in profile …"), and the debug script's
`note` field in `printDecoder`. `editor.usesFallbackDecoder` stays: the
machine learning captions use it.

## 5. A stored Look, and a stored decoder version, are not shown

- **Not shown anywhere.** No disabled pop-up, no caption, no badge, no Activity
  message (PRD non-goal), no tooltip, no VoiceOver text. A user cannot be
  asked to manage a value they cannot see or change.
- **Why no explanation for the photo that now looks different.** A photo saved
  as Flat or Neutral opens with the decoder's default contrast. The change is
  visible in the photo itself, the PRD records that the owner accepts it, and
  any text about it would have to name "Profile", the very thing removed.
  Explanation is one sentence in the user guide (§9) and the Ship note.
- **Reset All Adjustments.** It must clear a stored Look. See Requirements
  issue RI-1: R3's "every write keeps it" read literally would leave "Reset All"
  enabled on a photo that looks reset, forever, doing nothing. My ruling,
  until the product manager answers: Reset All (menu, ⋯ menu, grid batch)
  starts from the none value and so clears `look`; every other write keeps it.
- **"Edited" state.** `Adjustments.isDefault` compares the whole value, so a
  photo whose only content is a stored Look has Reset All enabled in the loupe
  (menu and ⋯ menu). That is the correct, honest behavior: it is the one control
  that can remove the stored value, and enabling it does no harm. No change.
- **History.** Entries made before this change keep their stored labels
  ("Profile", "Decoder"): a label is text recorded at the time, like every
  other (edit-history design). Choosing an entry that differs from the current
  state only by `look` is a real revert (one new entry, one undo step) whose
  render does not change; that is by R11 and needs no special case.
- **A stored `rawDecode` that is turned off** (the person unchecked Profile
  earlier) is kept as stored, flag and all, and keeps rendering as today (a
  turned-off `rawDecode` does not apply its decoder version, `effective`). No
  UI can switch it back on and none is added (R5: no existing render changes).

## 6. Presets, copy and paste, batch

- **Preset group lists.** `Adjustments.Group.presetGroups` no longer holds
  Profile, so Save Preset's "Include" check boxes (a two-column grid, one fewer
  box), the preset manager's Include submenu and a preset's group line
  (`PresetText.groups`) simply do not list it. The Save Preset grid goes from 14
  boxes to 13, so its last row holds one box and an empty cell, which the code
  already handles (`NSGridCell.emptyContentView`). The first box is now White
  Balance.
- **Presets saved with Profile.** A preset's stored group list may still name
  `profile`; decoding it must ignore the unknown name (PRD R6, AC6), and a
  preset whose list becomes empty shows the existing line "No settings". An
  "All settings" preset saved while Profile existed (`encodeGroups` stored
  `nil`, meaning every group) is still "All settings"; one that listed every
  group but Profile, or Profile among others, shows the groups that remain.
- **Applying such a preset** replaces the groups that remain and does nothing
  for Profile. There is no message: an old preset applying one fewer thing is
  not an error, and Activity would be a message about something the person did
  not ask about.
- **Copy and Paste Adjustments, batch actions, Apply Preset.** No UI change.
  Copy no longer copies `rawDecode`; Paste no longer replaces it. A pasted
  stack's Color noise reduction (`noiseReduction.color`) still pastes as today.

## 7. Lightroom preset import

Where the report is shown: the import summary alert (`PresetActions.summary`,
"Some settings have no equivalent here and were left out or approximated
(number of presets): …") and, for packs, the report page's lists. Today a
profile that is not Standard, Neutral or Flat lands in that line as
**Profiles and creative looks (n)**; the three known names map to Look.

**Wording: keep "Profiles and creative looks".** No new string, no new key.
Reasons:

- The list names what the *source* preset contained, in the source's own terms,
  like its neighbors ("Calibration", "Point color", "Texture", "Retouching").
  Lightroom users know these as profiles and looks; the app's own UI no longer
  having a Profile heading does not make the term wrong here.
- The sentence around it already says "no equivalent here and were left out or
  approximated". For a profile it is "left out"; "approximated" is generic.
- It avoids a new catalog entry whose translations would repeat this one.

Rules for when the line appears (`CameraRawMapping.Converter.profile()`):

1. A named profile or look that is **not** the camera-standard family is
   reported: Flat, Neutral, "Camera …", "Adobe Landscape / Portrait / Vivid",
   creative looks and any other name. The photo is not changed by it.
2. **Standard-family names** (`standard`, `adobe color`, `adobe standard`,
   `default`, `embedded`) are **not reported**: the decoder's default is exactly
   what they ask for, so nothing is lost, and nearly every Lightroom preset
   carries one. Reporting them would put "Profiles and creative looks (N)" on
   almost every import and teach people to ignore the line. This departs from
   AC7 ("Flat, Neutral or Standard … a report line"): see RI-2.
3. **Monochrome** (`monochrome` in the profile name) is reported once, as Black
   and white (approximated), as today (`isGrayscale`); it does not also add the
   profile line.
4. Neither case inserts `.profile` into `groups` (there is no such group) or
   sets any `decode` value. A preset that carried only a profile has no groups
   and is imported as a preset with "No settings" (it still imports: AC6).
5. `CameraRawFeature.profile` stays (it is the report's entry); update its
   doc comment to "A camera profile or creative look; every one is left out
   except the standard ones, which are not reported." (code comment only).
6. The `.lrtemplate`/`.xmp`/`.dng` "this is a profile, not a preset"
   failure (`CameraRawSettings.Failure.profile`, `PresetImport` reason "a profile, not a
   preset") is a different case (a profile file given as a preset) and does not
   change.

## 8. Menus, shortcuts, help, accessibility

- **Menu bar:** nothing. No command named Profile, Look or Decoder exists
  (checked: no menu item, context-menu item or shortcut in `Sources/PhotoApp`
  names them). Nothing is added or renamed.
- **Toolbar, context menus, Help:** none. The Help menu holds Search only.
- **Accessibility labels removed with their controls:** the Profile and
  Decoder pop-ups' labels ("Profile", "Decoder"), the Profile group's check box
  ("Turn off Profile to compare" / "Turn on Profile"), and the note's combined
  element. `GroupToggle` and `AdjustSection`'s help strings are built from
  `AdjustText.title`, so nothing remains to fix.
- **VoiceOver order** in Light: heading, then White Balance (its check box,
  Mode, Temperature, Tint), Tone, Presence: unchanged except that its first
  element is the White Balance group. Light's reset and check box names do not
  change ("Reset Light", "Turn off Light to compare").
- **Keyboard:** no key changes. Full Keyboard Access reaches the same controls
  minus two pop-ups.
- **Debug script / `photocli`:** the debug script's `ml decoder <version>`
  command and the `decoder`/`note` fields of `print ml` are removed with the
  control (`DebugMachineLearningCommands`); `photocli adjustments` and
  `render --set look=…` as in the PRD (R8).
- **Catalog entries to delete** (the engineer confirms by search that nothing
  else uses them; `LocalizationTests` must stay green): `Profile`, `Decoder`,
  `Standard`, `Neutral`, `Flat` (all with the comment "RAW profile …"),
  `%@ (default)` (decoder version), `%@ (machine learning)`, "Turn off Use
  machine learning to choose another decoder.", and "macOS can't decode this
  raw file, so it's shown with a built-in profile that can't be changed. Color
  noise reduction isn't available." Keep `Profiles and creative looks`.

## 9. User guide (`docs/USER_GUIDE.md`)

Changes, by place. AC10 searches for the terms Profile, Look and Decoder
pop-up; none of the new text uses them.

1. **Editing at 100% (line 394).** "On raw files, White Balance, Profile and
   Noise Reduction stay soft while the value moves …" becomes "On raw files,
   White Balance and Noise Reduction stay soft …". Keep the parenthesis about a
   raw the app decodes itself.
2. **Raw files macOS can't decode (lines 414 to 415).** "Such a photo is shown
   with a built-in profile and a baseline look (brightness and contrast) made to
   sit close to …" becomes "Such a photo is shown with a baseline look
   (brightness and contrast) built in, made to sit close to …". The word
   "profile" goes: it is internal now.
3. **Same section (lines 431 to 435).** Replace "You adjust it like any other
   raw, with two differences. In the Adjust tab, under **Profile**, a note
   stands in place of its pop-ups (the built-in profile can't be changed), and
   Noise Reduction has **Luminance** only: **Use machine learning** is dimmed
   unless a paste or preset turned it on; it then says it isn't applied, and
   Luminance applies instead." with "You adjust it like any other raw, with
   one difference: Noise Reduction has **Luminance** only. **Use machine
   learning** is dimmed unless a paste or preset turned it on; it then says it
   isn't applied, and Luminance applies instead."
   The next sentence ("**White Balance** works as on any raw …") stays. Check
   the "two differences" count against the rest of the paragraph (the
   paragraph's later "These photos take longer to open" is not a difference in
   the Adjust tab and stays).
4. **Same section (lines 457 to 459).** "Pasted adjustments or presets from a raw
   macOS decodes keep their Profile and Color noise reduction, which do nothing
   here." becomes "Pasted adjustments or presets from a raw macOS decodes keep
   their Color noise reduction, which does nothing here."
5. **Machine learning noise reduction (lines 492 to 513).** Delete "The Decoder
   pop-up (Light ▸ Profile) shows the same setting as **9.dng (machine
   learning)** (or **9** for camera raw files); choosing it turns machine
   learning on, and choosing another version turns it off and uses that
   version." Nothing is added: the paragraph already says "select **Use machine
   learning** at the top of Details ▸ Noise Reduction", which is what R10 asks
   (it is chosen with Use machine learning).
6. **Color Fringes (lines 555 to 558).** "(For a raw file, White Balance and
   Profile are applied as the file is decoded, before that point. After a large
   White Balance change or a different Profile, show the Fringe Map: …)" becomes
   "(For a raw file, White Balance is applied as the file is decoded, before that
   point. After a large White Balance change, show the Fringe Map: …)".
7. **A change for earlier photos.** One sentence in the Adjust tab's first
   place that describes raw rendering (engineer picks the nearest paragraph,
   after the White Balance description, line 435 region): "A raw always opens
   with its decoder's own contrast and color rendering; the Adjust tab has no
   choice of base rendering, and photos edited in an earlier version with a
   flatter or more neutral base now open with the decoder's default, their other
   edits unchanged." It names no removed control. Delete it at the next
   reconcile after a release has carried it; it is not a permanent part of the
   guide (product manager's call).
8. **Lightroom presets (lines 601 to 603).** Add "profiles and creative looks"
   to the list: "Lightroom settings with no equivalent here (calibration,
   masks, texture, crop, lens corrections, profiles and creative looks and the
   like) are left out, and the import lists them." (Profiles are an ordinary
   unsupported setting now, so they belong in that list.) Standard-family
   profiles are not listed (§7 rule 2).
9. The Adjust tab order sentence in `docs/UI_REDESIGN.md` ("Light with Profile,
   White Balance …") is a historical record; **do not edit it** (WORKFLOW:
   History).

## 10. Answers to the PRD's open questions for the designer

| Question | Answer |
|---|---|
| The Lightroom report line's wording for an unsupported profile | Keep "Profiles and creative looks"; no new string (§7). Standard-family names are not reported: RI-2 |
| Whether Develop's heading looks right starting at White Balance (reset, modified dot) | Yes (§2). It is how a rendered image's Light already looks. There is no "modified dot": the heading has a check box (shown only while one of its groups is modified, mixed when only some are on) and a reset arrow, both computed from the three remaining groups. A photo whose only content is a stored Look has neither |

## 11. Requirements issues for the product manager

**RI-1: Does Reset All Adjustments clear a stored Look?** R3 says every write
of the stack keeps `look`, and AC3 lists "batch action". Read literally, Reset
All (a batch action in the grid, a menu and ⋯ command in the loupe) would keep
the invisible value, so a photo whose only edit is a stored Flat keeps Reset
All enabled after Reset All, and `isDefault` stays false forever; the person
cannot remove it. Recommendation: Reset All clears `look` (and the stored decoder
version, with the whole `rawDecode` operation), because "reset" means "back to a
never-edited photo". Every other write keeps it. Needs R3 and AC3 to say "except
Reset All". If the answer is "keep it", the design change is only that Reset
All in the loupe stays enabled for such a photo; the engineer then makes
`canResetAll` ignore `rawDecode`.

**RI-2: Should a Standard-family profile appear in the Lightroom report?** R7
and AC7 say a Flat, Neutral or **Standard** profile is reported. Standard,
Adobe Color, Adobe Standard, "default" and "embedded" are what the decoder
renders anyway, and nearly every Lightroom preset names one. Reporting them
fills every import with "Profiles and creative looks (N)", which tells the person
nothing was lost when nothing was. Recommendation: report everything except the
standard family (§7); change AC7 to "A preset with a Flat or Neutral profile
imports with a report line for the profile and no Look set; one with a Standard
profile imports with no report line for it". If the owner prefers every name
reported, the design is unchanged except that rule 2 goes.

## 12. For the review (step 4)

Design requirements the review will check:

| # | Requirement | Check |
|---|---|---|
| D1 | Light starts at White Balance for a system raw, a LibRaw photo and a rendered image; no Profile heading, pop-up or note | Debug script `buttons`/`print`; by eye |
| D2 | Light's check box, reset and "Reset Light" computed from White Balance, Tone, Presence only | Script and test |
| D3 | Use machine learning in Noise Reduction as before: position, states, captions, badge | `ml` script commands |
| D4 | No string, catalog entry, undo name or accessibility label names Profile, Decoder or Look as a control | Search of Sources and the catalog |
| D5 | Save Preset and the preset manager list no Profile; an old preset with it imports and applies without error | Test and by eye |
| D6 | Lightroom import: Flat or Neutral reported once as "Profiles and creative looks", none set, Standard family per the ruling on RI-2 | Test |
| D7 | User guide changes of §9 made; AC10 search clean | Search |

Manual checks for a person (to be copied to `qa.md`): M1 Light in the light and
dark appearance and with Increase Contrast, on a system raw, an X-E3 file and a
JPEG (a heading that starts at White Balance, spacing equal to today's JPEG);
M2 a photo saved earlier as Flat opens with the decoder's default and its
history still lists and reverts the old entries; M3 Save Preset's Include grid
and a preset manager row whose preset had only Profile ("No settings").
