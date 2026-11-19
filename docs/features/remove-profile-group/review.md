# Remove the Profile group: design review

Reviewer: apple-ui-designer. Date: 2026-11-18. Issue #219. Branch
`feature/remove-profile-group`, read against [`design.md`](design.md) (D1 to
D7, M1 to M3), the PRD (issue body, revised 2026-11-18: RI-1 and RI-2 ruled),
`status.md` and the HIG (Consistency, Hierarchy, Writing, Pop-up buttons,
Inspectors).

Method: code read only (no app run, no shell: the diff was read file by file,
not as a `git diff`). Searched `Sources/` (outside the vendored LibRaw), the
String Catalog and `docs/USER_GUIDE.md` for Profile, Decoder, Look, the removed
strings and the removed symbols. Not run: the debug script, the tests, the
bundle. Nothing here was checked on screen.

## Verdict

**Pass, with no required fixes.** The Adjust tab, the machine learning row, the
preset lists, the Lightroom report, the strings and the user guide all do what
the design says. Two nits and one design erratum below, none blocking. What
still needs a person is how the new Light heading looks and what an old preset
or photo does on screen (M1 to M6).

## Design requirements

| # | Requirement | Result | Evidence |
|---|---|---|---|
| D1 | Light starts at White Balance for a system raw, a LibRaw photo and a rendered image; no Profile heading, pop-up or note | Pass (code); look needs M1 | `DevelopControls.body` (`AdjustView.swift` 173 to 205) begins with `GroupLabel(.whiteBalance …)`; the `isRaw` / `usesFallbackDecoder` branch, `profile`, `decoderPopUp`, `lookTitle` and `fallbackDecoderNote` are gone. One layout for every photo, as a JPEG's was |
| D2 | Light's check box, reset and "Reset Light" computed from White Balance, Tone, Presence only | Pass | `Adjustments.Section.develop.groups` is `[.whiteBalance, .light, .presence]` (`Adjustments.swift` 322); `Group` has no `profile`; `AdjustSection` / `SectionToggle` read `section.groups` (help strings still "Reset \(title)", "Turn off \(title) to compare"); `isModified(section)` is `resetting(section) != self`, and `rawDecode` belongs to no group, so a photo with only a stored Look has an unmodified heading |
| D3 | Use machine learning as before: position, states, captions, badge | Pass | `machineLearningRow` unchanged, still the first row of Noise Reduction above Luminance and Color; `MachineLearningText` keeps the `fallbackDecoder:` captions (S4, S6) as ruled; `decoderItem` and `decoderDimmedHelp` are gone; the Color row still hides on a LibRaw photo (`editor.isRaw`) and dims under machine learning |
| D4 | No string, catalog entry, undo name or accessibility label names Profile, Decoder or Look as a control | Pass | Catalog: the only matches for Profile / Decoder / Neutral / Flat are "Profiles and creative looks" (kept, ruled); "Standard" stays with its comment now naming the Export sheet; `%@ (default)`, `%@ (machine learning)`, the dimmed-pop-up tooltip and the LibRaw note are gone. `AdjustText.title(_ group:)` has no `.profile` case. No source file outside the Lightroom report names Profile or Look as a control. "Look-Up Table" and "Matte Look" (a pack tool name) are unrelated |
| D5 | Save Preset and the preset manager list no Profile; an old preset with it imports and applies without error | Pass (code); look needs M3 | All three lists read `Group.presetGroups` (13 groups: the Save Preset grid builds a last row with `NSGridCell.emptyContentView`; the manager's Include submenu; `PresetText.groups`). `decodeGroups` ignores unknown names; an empty set shows "No settings". Preset values keep the stored decode (`keepingStoredDecode`) and apply nothing from it except the legacy machine learning rule |
| D6 | Lightroom import: Flat or Neutral reported once as "Profiles and creative looks", none set; Standard family per RI-2 | Pass | `Converter.profile()` sets nothing and inserts `.profile` only for a non-standard, non-monochrome name; `standardProfiles` is the five names, compared trimmed and lower-cased; monochrome goes to `isGrayscale` (Black and white) only; `CameraRawFeature.profile`'s doc comment updated; `Failure.profile` ("a profile, not a preset") untouched, as §7 rule 6 says |
| D7 | User guide changes of §9 made; AC10 search clean | Pass, one nit (N1) | Changes 1 to 6 and 8 are in at the places the design names (100% paragraph, the app's own decoder paragraph, the paste sentence, the machine learning paragraph, Color Fringes, the Lightroom list). The search finds no Profile, Look or Decoder pop-up in `docs/USER_GUIDE.md`; "profiles and creative looks" and "A standard profile…" remain in the Lightroom paragraph, as designed. `docs/UI_REDESIGN.md` line 426 is untouched, as required |

Other things checked against the design:

- **§5 stored values stay invisible.** No control, caption, badge, tooltip,
  Activity message or debug-script field shows a stored Look or decoder
  version (`photocli` and the debug script no longer print them).
- **§8 debug script.** `ml decoder`, `adjust look` and the `note` field of
  `print ml` are removed; `printDecoder` keeps `decoder`, `wb` lines only.
- **RI-1 (Reset All clears it).** The loupe menu and ⋯ menu enable Reset All
  from `!adjustments.isDefault`, and `resettingAll()` keeps only unknown
  operations, so Reset All is enabled on a photo whose only edit is a stored
  Look and disabled after it. The grid batch and `AdjustmentEditor.resetAll`
  use the same function.
- **Spacing and no new component.** No metric, inset or component changed.

## Findings for the engineer

None required. Optional:

- **N1 (nit, user guide).** The one-sentence change for earlier photos (§9
  item 7) sits right after the "Editing at 100%" paragraph, a place about live
  frames. The design left the paragraph to the engineer ("the nearest
  paragraph, after the White Balance description"); the nearest paragraph
  about raw rendering is the "Raw files macOS can't decode" one, whose subject
  is another thing, so there is no good home. It reads fine where it is. Leave
  it unless the product manager wants it moved; it is to be deleted after a
  release has carried it (design §9.7).
- **N2 (nit, catalog comment).** The key `Light` has the translator comment
  "Adjust tab group of exposure and tone sliders", while the Swift comment on
  the Adjust heading now says "white balance, tone, presence" (design §2 asked
  for that update). The key is shared with another use (the Export sheet's
  sharpening amount "between Light and Strong"), which is probably why the
  comment is generic; if the comment is touched, it should say both uses.
  Translators see the catalog's comment, not the Swift one.

## Design erratum (mine, no action)

Design §6 says a preset that "listed every group but Profile" shows the groups
that remain. With Profile no longer a group, a stored list of the remaining 13
equals `presetGroups`, so `includesEveryGroup` is true and the preset shows
**All settings**, and is stored as `nil` the next time it is written. Applying
it replaces the same 13 groups it always did, so nothing the person sees in
behavior changes, and "All settings" is the accurate label now. Not a defect.

## Not done by this change, for Ship

- `README.md` line 92 ("a built-in profile and a baseline look") is the
  internal camera color profile (#170), not the removed group: it is still
  true. `CLAUDE.md` #161 entry ("no Profile or Decoder choice") and Phase 3
  entry ("profile, white balance …") are stale for the product manager at Ship,
  as `status.md` says.
- `status.md` RI-E1 (`photocli` can still set `rawDecode.decoderVersion`) is a
  scope matter for the product manager. It is not UI, so the design has no
  objection: the design's rule (no *control* sets a decoder version except Use
  machine learning) holds.

## What's working

- One Light layout for every kind of photo, with no placeholder row or note
  to explain an absence; the heading's controls follow from the groups.
- Use machine learning left where it was, with every state and caption
  unchanged; the Color row hides rather than dims where it can never apply.
- A stored Look is invisible and harmless, and Reset All is the one honest way
  to clear it.
- Reporting only what a Lightroom preset really loses (no "Profiles" line on
  nearly every import).

## Manual checks for a person

Run the bundle from the standing command on a scratch library (`--library-root`
always). Needs no VoiceOver, macOS 15 or macOS 26.

- **M1 (D1).** Open the Adjust tab on a system-decoded raw, on a LibRaw photo
  (an X-E3 or other file macOS can't decode) and on a JPEG, in the light and
  the dark appearance and with Increase Contrast. Light's first row after the
  heading is White Balance, with the same space under the heading as a JPEG
  has today; no Profile row, no note, no gap where one was. Resize the
  inspector narrow and wide: nothing clips.
- **M2 (R2, R11).** A photo saved earlier as Flat or Neutral opens with the
  decoder's default contrast and no sign of it in the tab. Its History panel
  still lists the old entries ("Profile", "Decoder"); choosing one adds an
  entry and does not change the picture.
- **M3 (D5).** File ▸ Save Preset: the Include grid has 13 boxes, White
  Balance first, last row one box and an empty cell, aligned like the others.
  In the preset manager, a preset that held only Profile reads "No settings";
  an old "All settings" preset still reads "All settings".
- **M4 (judgment).** Apply a "No settings" preset (from M3) to a photo: it does
  nothing, and adds no empty History entry or Undo step. If it adds either,
  that is a finding.
- **M5 (RI-1).** On a photo whose only stored edit is a Flat Look: the Light
  heading shows no check box and a dimmed reset arrow; Reset All Adjustments
  (menu and ⋯) is enabled, clears it, and is dimmed afterwards. Do an
  exposure edit first and confirm the Look survives it (not visible, so by
  the debug script's `print` of the stack or `photocli adjustments`).
- **M6 (D3).** On a system raw: Use machine learning is the first row of Noise
  Reduction, tooltip and caption as before. On the LibRaw photo: the check box
  is dimmed with "Not available for this camera.", Luminance only, no Color
  row, and no note anywhere in Light.
- **M7 (D6).** Import one Lightroom preset with a Flat profile, one with Adobe
  Color or Standard and one with both a Flat profile and a Monochrome look: the
  summary says "Profiles and creative looks" for the first, nothing about the
  second, and for the third Black and white only. The photo is unchanged by the
  profile in all three.

## Requirements issues

None.

## Summary for the issue

Design review of #219: **pass, no required fixes** (code read only; nothing run on screen).
- D1 to D7 met: Light starts at White Balance for every photo, its check box and reset come from the three remaining groups, Use machine learning is unchanged, no Profile, Decoder or Look string is left, preset lists drop Profile, the Lightroom report follows RI-2, the user guide is updated.
- Two nits (user guide placement of the earlier-photos sentence, a catalog comment) and one erratum in design §6; none needs a change.
- Open: manual checks M1 to M7 (the look in both appearances and Increase Contrast, an old Flat photo and its history, Save Preset's grid, a "No settings" preset, Reset All on a stored Look, the LibRaw photo, a Lightroom import).
- Ship: README and CLAUDE.md wording for the product manager; `photocli` can still set a decoder version (RI-E1, not UI).
- Full review: `docs/features/remove-profile-group/review.md`.
