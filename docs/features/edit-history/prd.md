# Edit history

Status: Approved
Slug: edit-history
Roadmap: Now

## Problem
A photo's edits are one current state. The window's undo steps are the only
record of how it got there, and they live in memory, are shared by every
photo in the window, mix in culling and keywords, and are gone at relaunch.
Someone who tries several looks cannot see what they did to this photo or go
back to an earlier state of it without undoing step by step, and not at all
after quitting.

## Goal and success
Each photo keeps a list of its edit states that survives relaunch. The person
sees it while in the loupe and can return the photo to any listed state. It
worked if, after a session of edits and a relaunch, the owner can open the
photo, find an earlier state in the list and return to it in one click, and
then undo that.

## Users and scenarios
- Primary: the person edits a photo through ten changes, dislikes the last
  four, opens the history in the loupe and clicks the entry before them. The
  photo shows that state. They keep editing from there.
- Edge: they quit, relaunch next week, open the photo and still see the list.
- Edge: they paste adjustments onto 200 photos; each photo gets one entry.
- Edge: an offline master, a video, or a photo whose stored edits this build
  cannot read: no usable list (see R12, R13).

## Requirements
R1 (Must): Every saved change to a version's edit stack records one history
entry for that version. A slider drag, a crop session saved with Done, and
one paste are each one entry, matching the undo step the same action makes.
R2 (Must): An entry has a short label naming the change (the same wording as
the undo action name, for example "Exposure", "Paste Adjustments", "Crop"),
and when it was made.
R3 (Must): History is stored per version in the library (a new catalog
migration) and is there after quitting and relaunching.
R4 (Must): The loupe offers a way to show the open photo's history as a
scrollable list. How it is reached and where it sits is for the designer
(owner's stated preference: see Open questions).
R5 (Must): The list marks which entry matches the photo's current state.
R6 (Must): Choosing an earlier entry puts the photo in the state it had then.
The change is saved like any edit, records a new entry (labeled as a
revert to the chosen entry) and no earlier entry is removed or changed.
R7 (Must): A revert is one undo step on the window's undo manager. Undo and
redo work as before (Redo stays ⇧⌘Z; no new redo key).
R8 (Must): Undo, redo and revert each change the stack and so each record an
entry (labeled for what they were), keeping the list a complete log.
R9 (Must): Each version has its own history. In a RAW+JPEG pair, edits are per
file, so each file's history lists only its own changes.
R10 (Must): A batch action (paste, preset, Auto Exposure, Reset All, Rotate)
records one entry per photo it changes, and none for a photo it leaves
unchanged.
R11 (Must): A history holds at most 100 entries per version and is also
trimmed to a byte budget per version (set and recorded by the engineer).
Snapshots are stored LZFSE-compressed. Past either limit the oldest entries
are dropped; the newest entry is always kept. There is no command to clear
history.
R12 (Must): For a video or an offline master (no editing), the history is
empty or unavailable and nothing breaks. It is not shown in the grid or in
review mode.
R13 (Must): For a stack this build cannot read (newer schema, damaged, over
limits), history is not written and the list is unavailable; the existing
rule that such a stack is never written over holds.
R14 (Should): Text for the list and its states goes through the String
Catalog, and the list is reachable and readable with VoiceOver and the
keyboard.
R15 (Should): Opening the list for a photo with a long history does not
delay showing the photo.
R16 (Could): Entries show a tiny summary of what changed beyond the label.

## Acceptance criteria
AC1 (R1, R2): Change Exposure with one drag, then crop and press Done: the
photo has two entries, labeled Exposure and Crop, each with a time.
AC2 (R3): After the edits in AC1, quit and relaunch (same library): the
photo's list shows the same two entries.
AC3 (R4): With a photo open in the loupe the list can be opened and scrolled
when it has more entries than fit.
AC4 (R5): The entry matching the current state is marked; after a new edit
the marker is on the newest entry.
AC5 (R6): Select the first entry of three: the loupe renders the state of
that entry (stack equals the stack saved then), and the list now holds four
entries with the first three unchanged.
AC6 (R6): After AC5, one more edit adds a fifth entry and the first three
are still there.
AC7 (R7): After a revert, Edit ▸ Undo returns the photo to its state before
the revert and ⇧⌘Z redoes it; no ⌘Y is bound.
AC8 (R8): Undo of an edit adds an entry; the stack after it equals the stack
before that edit.
AC9 (R9): For a RAW+JPEG pair, an edit on the RAW adds no entry to the
JPEG's history.
AC10 (R10): Pasting adjustments onto three photos, one of which already has
the same values, adds one entry to each of two and none to the third.
AC11 (R11): After 101 saved changes to one photo its list holds 100 entries
and the first one is gone; the oldest 100 are not editable by a clear
command (none exists).
AC11a (R11): With entries whose snapshots together exceed the byte budget,
the oldest are dropped until the history fits, the newest entry is kept even
if it alone exceeds the budget, and a stored snapshot reads back to an
identical stack.
AC11b (R6, ruling 5): Reverting to a state the photo already has adds no
entry. A copied version (`duplicateVersion`) starts with an empty history.
AC12 (R12): A video and an offline photo open in the loupe show no usable
history and no error; the grid and review mode have no history control.
AC13 (R13): For a photo with an unreadable stack, the list is unavailable and
the stored stack is byte-identical after the app opens it.
AC14 (R14): With VoiceOver the list's entries are read with label and time
and an entry can be chosen by keyboard (designer's manual check).
AC15 (R15): With a photo that has 100 entries, the loupe shows the photo as
fast as with none (compare on a scratch library; the engineer proposes the
measure).
AC16: No render changes: existing stacks render and hash as before, and no
golden moves.

## Non-goals
- No history of culling, ratings, keywords, albums or other metadata.
- No ⌘Y, no new redo key.
- No history for a whole library, a project or a selection, and no
  cross-photo history list.
- No clear, delete or edit of entries; no named snapshots or favorites.
- No history in sidecars or exports; originals are never touched.
- Not shown in the grid or review mode.
- No branching view and no merge of histories.
- Comparing two entries side by side belongs to side-by-side-comparison.

## Dependencies and impact
- New catalog migration (never edit an existing one); the engineer decides
  what an entry stores to make a revert exact. A stack snapshot per entry
  is the likely way, with the 100-entry cap bounding size.
- Every route that writes a version's stack must record an entry: the loupe
  editor, batch actions (`BatchEdit`, `changeAdjustments`), undo, presets,
  and Reset. Whether `photocli develop` and the mask commands do is Q2.
- Touches the loupe and the window's undo; the write chain (`WriteChain`)
  ordering rule must hold, so an entry is saved with its edit, not after.
- Related, not blocked: virtual-copies (a copy's history), side-by-side-comparison.

## Assumptions
A1: History starts at the first change after this feature lands; photos
edited earlier have no entries for the past. The state they had then is the
starting point and has no entry (the list simply begins).
A2: Undo, redo and revert are each logged as entries, so the list never
loses a state (R8). Clutter is the trade; the owner has not seen it.
A3: The cap counts all entries, including reverts and undos.
A4: Entries are labeled with the undo action name, so wording stays in one
place.
A5: A revert to the entry that is already current does nothing.
A6: Deleting a version or its photo from the catalog deletes its history.

## Open questions
- Ordering (owner undecided; designer to propose): newest on top is the
  working default, because the current state is always visible and nothing
  needs scrolling to the bottom. The alternative is oldest on top with the
  list scrolled to the end.
- Placement (designer): the owner's stated preference is a collapsed tab in
  the left sidebar while in the loupe, which slides a panel up. It is a
  preference, not a requirement. The sidebar currently holds sources only,
  and the inspector, toolbar or a popover may fit better; the designer
  should weigh it against the HIG and say.
- Q1 (closed): owner ruling 1.
- Q2 (closed, owner part): owner ruling 3. The engineer still confirms how.
- Q3 (closed): owner ruling 2.
- Q4 (engineer): what an entry stores, size of 100 snapshots on a large
  library, and the measure for AC15.

## Owner rulings (2026-11-09)
1. Undo, redo and revert are logged as entries and count toward the cap (A2, A3).
2. No history before the feature, and no seed entry (A1). The assumption
   about a starting point is dropped: the list simply begins at the first
   recorded change.
3. A4-A6 are accepted. Edits made through `photocli` record entries like any
   other write through the catalog.
4. History snapshots are LZFSE-compressed, and each version's history is also
   trimmed by a byte budget besides the 100-entry cap. The newest entry is
   always kept. The engineer picks and records the budget (R11, AC11a).
5. A copied version starts with empty history and no seed entry (extends
   A1). Reverting to any state the photo already has is a no-op, with no new
   entry (engineer's decision, A5 widened; AC11b).
6. Engineer's RI-3 (labels stored as text in the creation language) and RI-4
   (AC15 met by a structural guarantee plus timing) are accepted as they
   stand, for an English-only app.
Ordering and placement stay open for the designer. Earlier the same day the
owner ruled on intake: edits only, persisted per photo, click to revert,
100-entry cap, undo/redo keys unchanged.

## Revisions
