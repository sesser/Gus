Issue: #241

# Preset list view: QA

Owner: qa-tester. Date: 2026-11-20. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/preset-list-view` at 27c29b7, on a Mac16,8 (Apple M4 Pro),
macOS 27.2.1 (26B131), Xcode SDK 27.2.

## Verdict

Passes: all ten acceptance criteria hold by test or by script, with no
findings for the engineer. What is left for a person is the look and the real
mouse and keyboard (P1 to P5, the designer's M1 to M5): macOS would not make the
scripted copy the active app, so no real click, key window or tracking-area
move was possible here. `swift build` and the full `swift test` are green.

## Build and tests

- `swift build`: pass.
- Full `swift test`: 1276 tests in 183 suites passed (78 s), the count
  `status.md` gives. Nothing red, so #229 did not show.
- The feature's four suites, run alone: `PresetsViewChoiceTests` (5),
  `PresetsBarGeometryTests` (7), `InspectorSegmentedWidthTests` (6),
  `PresetRowKeyTests` (5), all pass.
- `Scripts/build-app.sh`: pass.
- AC10 by diff against `develop`: no file under `Tests/PhotoCoreTests/Goldens`,
  none under `Sources/PhotoCore/Catalog`, and no change to
  `currentPipelineVersion` in any source file (the string appears only in
  the docs). `PresetPreviewModel.render`, `hover` and the 120 ms hold are
  unchanged: its diff is two debug counters (`debugRenderedCount`,
  `debugHoverEnds`).

## Acceptance criteria

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| AC1 (R1) | Test, Script, Person | `PresetsBarGeometryTests` (`nothingOverlapsAndTheSwitchIsAtTheRightEdge`: no overlap at every 0.5 pt from 60 to 420; `pushButtonsKeepTheirPlacesAndWrapAsBefore`; `measuredSizesWrapAtTheDefaultColumn`). Scripts S1 and S2: `buttons` shows one `NSSegmentedControl` 'Presets view', `selected 1`, segments Thumbnails / List, tips 'Show presets as thumbnails' / 'Show presets as a list'; `print presetsbar` shows the switch at x 215 to 271 on the first line, `clear`, accessibility two `AXRadioButton`s named Thumbnails and List with their tips as help, and arrangement 2 at the narrowest column with both scrollers (239 and 256 pt room) | Pass. The selected segment's look and dragging to the narrowest: P1, P3 |
| AC2 (R2, R3) | Test, Script | `PresetsViewChoiceTests` (nothing stored gives list, both values, garbage, round trip). Script S3: fresh domain `stored nothing` and list; choose thumbnails, relaunch: thumbnails; choose list, relaunch: list (`defaults read` gives `list`) | Pass. The choice made by a real click on a segment: P5 (the script sets the model value the control's binding sets) |
| AC3 (R4) | Script | S4: with Cool and Warm open the list shows 40 rows (946 pt), thumbnails 40 tiles (4,557 pt); the `buttons` names in order are identical in the two views (42 entries: 40 presets plus the two headings; same text tooltips 'Look 01 / Tone, Presence'); closing Warm and Cool in thumbnails shows them closed in the list (10 rows), opening them again gives 40; the stored `adjust.presets.<name>` values go 1, 0, 1 | Pass |
| AC4 (R5) | Script, Person | S5: in the loupe `preset row Look 03 press` gives undo 'Apply Preset Look 03', History one entry 'Apply Preset Look 03' (it starts empty); the same call on a thumbnail gives the same; S9: Return on a focused row applies ('Apply Preset Look 05'), Shift-Return does not. In the grid with one photo focused and selected, `preset row Look 02 press` gives undo 'Apply Preset Look 02' and one History entry on that photo (S5 grid variant). The context menu is from the one modifier both views share (`presetContextMenu`, read in code); SwiftUI menus can't be opened by the script | Pass for the apply; the menu itself and a real click: P4. |
| AC5 (R6) | Script | S6: in the loupe, hovering Look 03, Look 04, Look 05, Cool 15 in turn says `preview on loupe preview` each time and `ends 0` (the 120 ms hold ended nothing between rows); `hover end` says `preview off loupe saved ends 1`. Undo stack `-` and History 0 entries before and after. A run with the hovers and one without leave identical file lists in the library folder, previews included (55 files each) | Pass. The pointer path itself (a real tracking area, a fast sweep): P4 |
| AC6 (R6, R7) | Script | S7: thumbnails in the loupe preview on hover and end on leaving (`ends 1`); in the grid, in list and in thumbnails, `preview off`, `renders 0`, `mode grid`; during a crop session (the Crop heading shows 'Finish cropping') hover previews in the list and in the thumbnails alike, `preview on` then `off`. The crop case is the existing path: no rule was added (the model's diff is counters only) | Pass |
| AC7 (R8) | Script | S3 and S4: a list launch says `thumbnailRenders 0` with 10 and with 40 rows; switching to thumbnails renders 10 (or 40) and the tiles appear; relaunching in list gives 0 again | Pass |
| AC8 (R9) | Script | S8: after `preset row Look 03 press` the row's accessibility value is 'Applied to this photo'; after `undo` no row has one; after `redo` it is back; after `adjust exposure 0.9` none. `Cool 03` is marked too, because the seeded presets share identical values at the same index: that is the rule working (a preset the photo already has) | Pass. The mark's look: P1 |
| AC9 (R11) | Script, Person | S2 and S9: each row is a `PresetListRowButton` named for its preset (accessibility 'AXButton', help is name and groups); `preset row … focus` makes a row first responder (it accepts it); Return applies, `PresetRowKeyTests` covers Return, keypad Enter and fn-Return with Caps Lock on and the chosen modifiers not applying. Space is AppKit's button handling and could not be sent (no key window) | Pass for names, focus and Return. Tab order, Space, arrows on the segments with Full Keyboard Access: P2 |
| AC10 (R12) | Test | Full `swift test` green; no golden, no catalog file, no `currentPipelineVersion` change (diff above) | Pass |

Counts: passed by test 1 (AC10; the rules behind AC1, AC2 and AC9 are
also pinned by tests), by script 9 (AC1 to AC9), failed 0. No AC is open for a
person alone; the looks and real input behind AC1, AC2, AC4, AC5, AC8 and AC9
are P1 to P5.

## Findings

None for the engineer.

Notes, not findings:

- N1. `accessibilityPerformPress()` returns `false` on a list row although the
  press applies the preset (undo shows the step). A thumbnail's returns the
  same: it is `NSButton`'s own return value for these subclasses, and
  `HoverButton` is unchanged by this branch. Nothing to do.
- N2. The debug script's `key` runs in an empty undo group, so
  `key shift+return` on a row (which does nothing) leaves an undo name of
  `''`. A script artifact (`changing` in `DebugScript`), not an app step.
- N3. No unit test exists for AC3 to AC9 beyond the pure rules: no test target
  imports `PhotoApp`, as the code review noted. The debug script is their
  check, and this file's scripts rerun them.
- N4. Layout differs between launches by the window's position, so `buttons`
  x values in the scripts change; use names, not coordinates.

## Scripts

Setup, once. A scratch library from `photobench`
(`generate --jpeg 4 --dng 1`, 105 items with its default HEICs), `import`ed,
then 40 presets seeded by one scripted launch: 10 picked as files (no
collection, one with a very long name), and the folders `Cool` and `Warm`
(15 each) of Lightroom `.xmp` presets with distinct Exposure, Contrast and
Saturation. The bundle was copied, given the identifier
`me.sesser.gus.debugtest.presetlist` (`plutil -replace`) and signed ad hoc
(`codesign --force --deep --sign -`); every launch carried `--library-root`
on a fresh copy of the seeded library; the Presets heading was opened by
writing `adjust.section.presets` to that identifier's domain, whose
`adjust.presetsView` was deleted before S1.

    Gus.app/Contents/MacOS/Gus --library-root <copy of seeded library> --debug-script "<script>"

`P` below is `wait 2; inspector on; loupe; wait 1; tab adjust; wait 1`.

- **S1** (AC1, AC2: fresh domain): `P; preset view print; buttons; snapshot
  s1.png; quit`. Shows `list stored nothing thumbnailRenders 0 rows 10 tiles 0
  rowsHeight 220`, the switch row in `buttons` (above), the ten rows 259 pt
  wide. The snapshot shows the loupe and a blank inspector (a glass pane, as
  `CLAUDE.md` says).
- **S2** (AC1, AC9): `P; preset view print; print presetsbar; quit`. Shows
  arrangement 2 at the default column (visible 283, available 259, switch
  right of Save…/Import…, Manage… under Save…, `clear`), `needs 1 276.5 2 196.0
  3 138.5`, narrowest room 256 (overlay) and 239 (legacy) both arrangement 2,
  the switch's and rows' accessibility, and the indents (row text 20 pt with no
  collection, 26.5 pt under an open heading, equal to the heading's title).
- **S3** (AC2, AC7): four launches, same domain.
  `P; preset view print; preset view thumbnails; preset view print; quit`,
  then `P; preset view print; quit`, then `P; preset view list; quit`, then
  `P; preset view print; quit`. Shows `list stored nothing renders 0`, then
  `thumbnails stored thumbnails renders 10 tiles 10`, then on relaunch
  `thumbnails`, then `list`, with `renders 0` on the last.
- **S4** (AC3): `P; preset view list; preset view print; preset heading Cool;
  preset heading Warm; preset view print; preset view thumbnails; preset view
  print; preset heading Warm; preset heading Cool; preset view print; preset
  view list; preset view print; preset heading Cool; preset heading Warm; preset
  view print; print presetsbar; quit`, and `P; preset view list; buttons;
  preset view thumbnails; wait 1; buttons; quit` for the order and tooltips
  (compared with a short Python script over the output). Rows 10, 40, 40;
  tiles 40 then 10; the names in the same order in both views.
- **S5** (AC4): `P; preset row Look 03 press; print undo; history; quit`, its thumbnails variant, and a grid variant
  (`wait 2; inspector on; grid; wait 1.5; focus 0; wait 1; tab adjust; wait 2; preset view print; preset row Look 02 press; wait 1; print undo; loupe; wait 1.5; history; quit`).
  `undo 'Apply Preset Look 03'`, History one entry; in the grid 'Apply Preset Look 02' on the focused photo.
- **S6** (AC5): `P; preset view list; history; print undo; hover name Look 03;
  hover name Look 04; hover name Look 05; hover name Cool 15; hover end;
  print undo; history; quit`, with two further launches (with and without the
  hovers, `wait 3; quit`) whose library folders were compared with `find`.
- **S7** (AC6): `P; preset view thumbnails; wait 1; hover name Look 03; hover
  name Look 04; hover end; undo; print undo; history; quit`;
  `wait 2; inspector on; grid; wait 1; focus 0; tab adjust; wait 1; preset view
  list; hover name Look 03; hover end; preset view thumbnails; wait 1; hover name
  Look 03; hover end; print undo; quit`; `P; preset view list; adjust crop
  begin; wait 1; hover name Look 03; hover end; preset view thumbnails; wait 1;
  hover name Look 03; hover end; quit`.
- **S8** (AC8): `P; preset row Look 03 press; wait 1; print presetsbar; undo;
  wait 1.5; print undo; print presetsbar; redo; wait 1.5; print presetsbar;
  adjust exposure 0.9; wait 1.5; print presetsbar; print undo; quit` (the
  marks read from the rows' accessibility values: none, Look 03, none).
  Waits matter: without them the print runs before the save.
- **S9** (AC4, AC9): `P; preset view list; preset row Look 05 focus; key
  shift+return; wait 1.5; print undo; key return; wait 1.5; print undo; preset
  row Look 03 press; wait 1; preset row Look 07 focus; undo; wait 1; print undo;
  quit`. Return applies Look 05, Shift-Return nothing, focusing adds no undo
  step.
- **S10** (real input, not possible): `open -W -n --stdout <log> <copy> --args
  --library-root <lib> --debug-script "wait 8; …; click …"` twice, the second
  time bringing the process forward by its ID with System Events. Both gave
  `key nil` and empty `hits` for the clicks: macOS did not make the copy the
  active app. Not retried further; the clicks, Space and the tracking area
  are P-items.

After the runs: no scratch instance running, and no file in the owner's
`~/Library/Application Support/Gus/Library` newer than the start of QA.
One scripted launch without `quit` (my mistake) was stopped by its process ID.

## For a person

VoiceOver, macOS 15 and macOS 26 are not asked (standing ruling). Build and run
the bundle on a scratch library with the command under Follow-up. Open the
Adjust tab with a photo in the loupe; the Presets heading is already open.

- **P1** (designer M1) Look of the list, in Light, Dark and Increase
  Contrast: the hover fill, the pressed fill while the button is down, the
  check mark on the applied preset (apply Look 03: Look 03 and Cool 03 both
  show it because the seeded values coincide), 22 pt density, the very long
  name cut at its tail with its full name in the tooltip. Change the accent
  color (and Graphite) with the app open: the mark follows and the selected
  segment is clear. The switch beside the push buttons: same height.
- **P2** (designer M2) Turn on Full Keyboard Access. Tab from the Presets
  buttons: the switch once, then each row, no control skipped or repeated. Left
  and right arrows move between the segments; Space on a segment changes the
  view. On a row the focus ring is visible on all four sides (first row, last
  row, a row under an open collection), not cut at the column edge or painted
  over by the next row; Space and Return apply. If the ring is clipped, that is
  the designer's conditional 2 pt inset (review.md Improvements 1).
- **P3** (designer M3) The button row. At the default inspector width Manage…
  sits under Save… with the switch at the right of the first line (design
  §16.1: expected), with an overlay scroller and with "Always show scroll
  bars". Drag the inspector from narrowest to wide and back: the switch is
  never on a push button, nothing flickers, and a keyboard-focused switch stays
  focused while you drag. The same with no presets and on the grid tab. A real
  click on each segment changes the view and the chosen segment is plain to see.
- **P4** (designer M4) A real mouse, in the loupe: sweep slowly and fast down
  the list (Cool and Warm open): the photo shows each preset in turn with no
  flash of the original between rows, and returns to its own edits on leaving.
  Scroll with the wheel under a still pointer. Right-click a row: Apply and
  Manage Presets…. Click a row: one undo step; the mark appears and goes with
  undo and redo. Hover does nothing in the grid.
- **P5** (designer M5) Switching: with a long list scrolled halfway switch to
  Thumbnails and back (no unexpected jump; thumbnails fill in; the list returns
  at once). Quit and reopen: the choice is kept. Open a collection in one view
  and find it open in the other.

## Follow-up

No reruns were needed. To build the bundle and run it on a scratch library with 40
presets (zsh; the library, presets and a copy of the bundle with its own
identifier all live in `/tmp/gus-qa-241`; the last line carries
`--library-root`):

    cd ~/Projects/Gus-preset-list-view
    W=/tmp/gus-qa-241
    rm -rf $W && mkdir -p $W/src $W/presets/single $W/presets/Cool $W/presets/Warm
    Scripts/build-app.sh
    swift run -c release photobench generate --output $W/src --jpeg 4 --dng 1
    swift run -c release photobench import --library-root $W/lib --source $W/src
    python3 -I - $W/presets <<'PY'
    import sys, os
    root = sys.argv[1]
    t = '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:PresetType="Normal" crs:Version="15.0" crs:ProcessVersion="11.0" crs:Exposure2012="{e:+.2f}" crs:Contrast2012="{c:+d}" crs:Saturation="{s:+d}"><crs:Name><rdf:Alt><rdf:li xml:lang="x-default">{n}</rdf:li></rdf:Alt></crs:Name></rdf:Description></rdf:RDF></x:xmpmeta>'
    def w(folder, name, i, shift=0):
        with open(os.path.join(root, folder, name.replace(" ", "_")[:40] + ".xmp"), "w") as f:
            f.write(t.format(n=name, e=((i + shift) % 9 - 4) * 0.2, c=((i + shift) * 7) % 60 - 30, s=((i + shift) * 5) % 50 - 25))
    for i in range(1, 10): w("single", "Look %02d" % i, i)
    w("single", "A very long preset name that cannot possibly fit in the inspector column without truncation at its tail", 10)
    for i in range(1, 16):
        w("Cool", "Cool %02d" % i, i, 1)
        w("Warm", "Warm %02d" % i, i, 5)
    PY
    cp -R build/Gus.app $W/Gus.app
    plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.signoff241 $W/Gus.app/Contents/Info.plist
    codesign --force --deep --sign - $W/Gus.app
    defaults write me.sesser.gus.debugtest.signoff241 adjust.section.presets -bool true
    $W/Gus.app/Contents/MacOS/Gus --library-root $W/lib --debug-script "wait 2; preset import $(print -r -- $W/presets/single/*.xmp) $W/presets/Cool $W/presets/Warm; quit"
    open -n $W/Gus.app --args --library-root $W/lib

(Everything but the last line was run end to end by QA on 2026-11-20. With a
fresh preferences domain the heading opens in list view. To undo:
`rm -rf /tmp/gus-qa-241; defaults delete me.sesser.gus.debugtest.signoff241`.)

### Owner's sign-off

Signed off by the owner on 2026-11-21 (relayed by the main session), after
doing checks P1 to P5 by hand: no findings, and no checks left open.

- Code signed off: `27c29b7` (the last commit that changed source or tests;
  the code tested). This `qa.md` was at `ec22705`. The commit after it, the
  merge of `develop` into the branch, changed none of them.
- P1 to P5: done by the owner, fine.
- Not checked by a person: VoiceOver, macOS 15 and macOS 26, covered by CI
  only (standing ruling).
