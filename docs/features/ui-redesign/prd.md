# UI redesign: requirements addendum

Status: Shipped 2026-11-05, PR #34 (ui-redesign-reconcile, E1–E28, which carries R1 and R2). AC2 and the other person-only checks, P1–P10 in qa.md "For a person", were checked by the owner on 2026-11-06: all passed, no findings.
Slug: ui-redesign
Roadmap: Shipped (the redesign 2026-11-04, PRs #20 and #21; `ui-redesign-reconcile` 2026-11-05, PR #34)

This is not a full PRD. The capability inventory,
[`../_inventory.md`](../_inventory.md), stands in for the redesign's PRD
(owner, 2026-11-04). This file supplements it with the product rulings on the
requirements issues RI-1 … RI-7 in [`design.md`](design.md) §5. Owner rulings
D1 and D2 (design.md §8) stand as written; nothing here changes them.

## Rulings

| RI | Ruling | Where it lives |
|---|---|---|
| RI-1 Help menu | No help content is in scope now. The dead "‹app› Help" item goes (R1), and searching menu commands stays (R2). Help itself is new scope | R1, R2 below; roadmap `in-app-help` (Later) |
| RI-2 Rename projects; remove photos and projects | In scope, and consistent with principle 1 as long as files are never touched. New scope that needs its own PRD, not part of this redesign. The catalog already has `renameProject` and `deleteProject` with no UI (inventory corrected) | Roadmap `remove-from-library`, `rename-project` (Next) |
| RI-3 Show in Finder | Wanted: it fits the vision (people keep files in their own folders). New, small scope. The title must not clash with Show Original (design's point) | Roadmap `show-in-finder` (Next) |
| RI-4 Which metadata reader is in use | Worth showing, but new scope. If built it is passive, never an alert | Roadmap `metadata-reader-status` (Later) |
| RI-5 `docs/USER_GUIDE.md` owner | **Owner ruling, 2026-11-04** ("Engineer, designer reviews"): the engineer updates the guide in the same change as the behavior it describes, and the designer checks its terms at review. Recorded in `docs/WORKFLOW.md` Ownership. E27 is unblocked | Owner rulings below |
| RI-6 edit-history vs this design | The edit-history PRD will state the need only. ⌘Y and left-sidebar placement from issue #26 are proposals for design, not requirements. ⇧⌘Z stays the redo key for the app as shipped | Roadmap `edit-history` row (Next), intake notes |
| RI-7 Photo pasteboard | New scope, separate from publishing-engine and partly overlapping export-extras. Until it ships, design X5 stands: Edit ▸ Copy and Cut/Paste are text-only and dimmed in the grid and loupe | Roadmap `photo-pasteboard` (Later) |

## Requirements

R1 (Must): Neither the library app nor the standalone importer shows a menu
item that only reports that help isn't available.

R2 (Should): Help ▸ Search, the system field that finds menu commands, stays
available in both apps after R1. It supports principle 5 (every command is in
a menu, so people can find it there).

## Acceptance criteria

AC1 (R1): In each app, the Help menu has no "‹app› Help" item, checked with
the debug script's `menuitems Help` in the library app and by hand in the
importer.

AC2 (R2): Manual, in each app: open Help, type "Export" (library app) or
"Rescan" (importer); the matching File menu item is offered and highlighted.

## Non-goals

- Writing help content or choosing its form (`in-app-help`).
- Any of the new scope in the Rulings table. Each gets its own PRD from
  intake.
- Changing D1 or D2.

## Assumptions

- Help ▸ Search is available in a SwiftUI app with no Help Book. If removing
  the item also removes the menu, R1 wins over R2 (see Q2).
- A dead menu item is a defect against principle 4 (native first, HIG), not
  new scope, so I ruled R1 without the owner. The HIG's menu bar page does
  not cover apps with no help content; this is judgment. The owner can
  overrule it.

## Owner rulings

- **RI-5 (ruled 2026-11-04).** `docs/USER_GUIDE.md` is updated by the
  engineer in the same change as the behavior it describes; the designer
  checks its terms at review. Owner's words: "Engineer, designer reviews".
  The row is in `docs/WORKFLOW.md` Ownership. For E27 the guide is stale in
  four places: the Import window's "Include videos switch" (now Show
  Videos), the key table's blank loupe column for ⌘= / ⌘− (design I30),
  export problems raising an alert (D2, E14), and "caption" in the Export
  metadata paragraph (Description after E16). Each is fixed in the change
  that ships its behavior; the first two describe behavior already shipped
  and go with E27.

## Open questions

- **Q2 (engineer), answered 2026-11-05 (status.md, E28): Does R1 keep R2?**
  As far as the debug script can tell, yes: with the help item gone, both
  apps keep the Help menu, and AppKit still treats it as the help menu that
  gets the search field. The field is drawn only when the menu opens, so
  AC2 stays a manual check in each app.
- **Q3 (designer), resolved 2026-11-04:** Update N13 and the "‹app› Help"
  row in design.md §4 to follow R1 and R2. Done: design.md N13, the §4
  "Help ▸ Search ⌘?" row, and engineer change E28 (verified by AC1 and AC2).

## Revisions

- 2026-11-04: Q1 (who owns `docs/USER_GUIDE.md`) answered by the owner with
  the proposed default; moved to Owner rulings as RI-5. Q2 and Q3 keep their
  numbers.
- 2026-11-04: Q3 marked resolved; the designer updated design.md N13 and
  the §4 Help row, and added E28 for AC1 and AC2. Q2 stays open.
- 2026-11-06: Ship pass. ui-redesign-reconcile merged into `develop` in
  PR #34 (merge commit 1e89a7b, 2026-11-05) with E1–E28 Done (status.md).
  AC1 is checked by the debug script; AC2 is manual and pending. Q2 marked
  answered from status.md. Changed the Status and Roadmap lines.
- 2026-11-06: Owner ruling: "I've checked all the P1-P10 of the
  ui-redesign", all passed, no findings. AC2 is verified; "checks pending"
  removed from the Status line. qa.md's Follow-up does not record it yet.
