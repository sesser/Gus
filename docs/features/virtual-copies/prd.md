Issue: #62

# Virtual copies

Status: Approved (owner, 2026-11-11)
Slug: virtual-copies
Roadmap: Next

## Problem
A photographer wants two or more treatments of one photo (color and black and white, two crops, a before-the-risky-edit snapshot) without importing the file twice. The catalog can already hold several versions of one master and `Catalog.duplicateVersion` makes one, but nothing in the app calls it. Today the only way is to reimport, which gives a second, unrelated photo.

## Goal and success
Make a copy of a photo in the library, edit it independently, and see it beside the original. Success: copy a photo, give the copy a different edit, and the original's edits, preview and history are untouched; the copy can be removed on its own.

## Users and scenarios
- Primary: select a photo, choose Duplicate (copy appears next to the original), apply a black and white preset to the copy, compare both in the grid.
- Edge: duplicate a RAW+JPEG pair; duplicate several selected photos at once; duplicate an offline photo; remove only the copy.

## Requirements
R1 (Must): A command makes a copy of each selected photo: a new version of the same master with the original's current edit stack, and one undo step for the whole action. The original is unchanged.
R2 (Must): The copy has its own edit stack, render hash, preview cache entries and edit history (starts empty, as `duplicateVersion` already does). Editing either never changes the other.
R3 (Must): The copy keeps its own rating, flag and color label, starting with the original's values.
R4 (Must): The copy starts with the original's keywords and album membership, then each changes independently (adding a keyword to the copy leaves the original alone).
R5 (Must): The copy shows in the grid, loupe, film strip and review mode as its own item, marked as a copy. It is placed right after its original when made; afterwards it sorts by its own values (so under a rating sort it may no longer sit beside the original; under capture-date and file-name sorts it stays with it). It is stackless and not a member of any stack the original is in.
R6 (Must): Removing a copy removes only that version (its edits, history, culling, keyword and album links). The master, the original and files are untouched. Removing the original takes its copies with it (R6 of library-ops: "everything the catalog holds for the photo"), and the confirmation says how many copies go.
R7 (Must): Copies never write or change a sidecar. Sidecars stay owned by the default version (the SQLite triggers already fire only for it), and a copy's changes queue nothing.
R8 (Must): Export of a copy renders the copy's edits, with its own name suffix so names do not collide when original and copy are exported together. Metadata written follows the existing export levels, from the image's descriptive fields and the copy's keywords.
R9 (Should): For a RAW+JPEG pair, duplicating either file duplicates only that file's version (edits are per file); the copy does not join the pair and does not share culling with the partner.
R10 (Should): A copy can be given a name (`version.name`) and can be made the default version of its photo. **Deferred at design (2026-11-11)**, see Decisions D9. Not part of this feature's acceptance.
R11 (Could): Filter or smart-album rule "is a copy".

## Acceptance criteria
AC1 (R1): Given a photo with edits, when Duplicate runs, then the catalog has one more version of that master with an equal stack; undo removes it, redo restores it.
AC2 (R2): Edit the copy; the original's stack, render hash, and history are byte-identical to before.
AC3 (R3): Rate the copy 5; the original's rating is unchanged, and the reverse.
AC4 (R4): The copy lists the original's keywords and albums; adding a keyword to the copy leaves the original's list unchanged.
AC5 (R5): The grid shows two items for the master, the copy marked; the sidebar counts and the window subtitle include copies. Right after Duplicate the copy sits next to its original.
AC6 (R6): Remove the copy; the original and its edits remain. Remove the original; its copies are gone and the confirmation named their number.
AC7 (R7): After duplicating and editing, rating and keywording the copy, `sidecarQueue` has no new rows and no `.xmp` is written or flagged.
AC8 (R8): Exporting original and copy together to one folder gives two distinct files whose pixels match their own edits.
AC9 (R9): Duplicating a pair's RAW leaves the JPEG's version untouched and unpaired from the copy; rating the copy does not change the JPEG.

## Non-goals
Copies that share one edit stack (a copy is a snapshot, not a live link); stacks or grouping of copies; merging edits back; copies in the standalone importer; copying the file on disk; syncing copies' culling to sidecars; side-by-side compare (own roadmap item).

## Dependencies and impact
Touches `Catalog.duplicateVersion` (needs keywords, albums and history decisions; today it copies the row only, so culling and stack but not keyword or album links), `ImagePairing` (writes reach the partner via the default version; a copy must be excluded), grid queries (`LibraryQuery` currently reads `version.isDefault`; whether it lists non-default versions must be checked), `LibraryRemoval`, export naming, `PhotoBench`, `photocli` (a duplicate command in the registry is a Could), Edit History, smart albums, USER_GUIDE. No migration is expected: `version` already holds `versionNumber` and `name` with a unique key on image and number.

## Decisions (owner, 2026-11-11: all proposed defaults accepted)
D1 (was A1): A copy keeps its own culling, keywords and albums, seeded from the original (R3, R4). Reason: a copy exists to be treated differently, and the catalog stores these per version.
D2 (was A2): A copy is a snapshot of the stack, not a live link.
D3 (was A3): Sidecars belong to the master's default version only; copies are catalog-only (R7). Reason: one `.xmp` per file, and the triggers already behave this way. A copy's rating or keywords are therefore not in any sidecar.
D4 (was A4): Removing the original removes its copies; removing a copy leaves the original (R6).
D5 (was A5): RAW+JPEG: copy is per file and unpaired (R9).
D6 (was A6): Copies count as items everywhere photos are counted.
D7 (was A7): Roadmap position (Next, after library-ops) is as the owner set on 2026-11-06.
D8: The seven intake questions were answered with their defaults: own culling, keywords and albums (D1); sidecar and export content (D3, R8); removal rules (D4); pair behavior (D5). Question 5, whether a copy can become the default version and take over sidecar ownership, stays with R10 (Should, deferrable): the engineer or designer may defer it if it widens scope, and the owner is told if so.

D9 (designer, 2026-11-11): R10 is deferred. Making a copy the default moves sidecar ownership (D3), changes which version a RAW+JPEG pair links through (`ImagePairing` works on default versions), changes which file's sidecar a later import reads, and changes grid order; each is a design and engineering problem of its own. Naming needs an editing surface, an undo step and export-name rules. Neither is needed for the goal, which a numbered copy ("copy 2") meets. Follow-up issue proposed: `copy-name-and-default`.

## Proposed, pending owner
P1 (RI-V1, pending owner): Videos are not duplicated. A video has no adjustments, so its copy could differ only in culling, keywords and albums. Duplicate is unavailable when no target is a photo; videos in a mixed selection are skipped and counted in Activity. Not confirmed by the owner; if the answer is yes, only the designer's photo rule, the video loupe line and the Activity row change. This reads R1's "each selected photo" as photos only.

## Open questions
Owner: P1 (videos). R10's deferral (D9) is for the owner to know about; it is filed as a follow-up.

## Revisions
- 2026-11-11, from design.md section 13: R5 sort wording (RI-V2); AC5 counts wording (RI-V3); R10 marked deferred (D9); videos recorded as proposed default P1, pending owner (RI-V1).
Designer: where Duplicate lives, how a copy is marked, how it is named in the grid and in file names.
Engineer: does the grid query list non-default versions today; how Remove from Library finds a copy's pair partner (`LibraryRemovalTests` already duplicate a version); what duplicate does to an unreadable stack; whether an offline photo can be duplicated (proposed: yes, catalog only).
