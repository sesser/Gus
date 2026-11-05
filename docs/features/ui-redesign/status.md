# UI redesign: implementation status

Owner: swift-macos-engineer. Tracks the engineer changes E1–E28 in
[`design.md`](design.md) §6 (feature `ui-redesign-reconcile`). Branch
`feature/ui-redesign-reconcile-impl`, cut from `develop` at `adb8d95`.

States: Not started · In progress · Done · Blocked (waiting on a question
below) · Deferred. "Commit" is the commit that finished the change.
"Manual" means a person has to look at the bundled app; those checks belong
to `ui-redesign-onscreen-check` unless noted.

## Build and test

- Baseline at `adb8d95` (2026-11-04): `swift build` clean; `swift test` 468
  tests in 84 suites passed, 1 known issue (the `withKnownIssue` in "Live
  render session", pre-existing).
- Latest: see the last commit on the branch; updated with each change below.

## Changes

| # | Pri | Change | State | Commit | Verified by |
|---|---|---|---|---|---|
| E1 | High | Empty-source states (N3) | Not started | | |
| E2 | Medium | Adjust tab states as `ContentUnavailableView` (N1) | Not started | | |
| E3 | Medium | Settings check boxes (I10) | Not started | | |
| E4 | Medium | Adjust ▸ Import Look-Up Tables… (N5) | Not started | | |
| E5 | Medium | Adjust ▸ Reset Crop (N6) | Not started | | |
| E6 | Low | Adjust ▸ Show / Hide Mask Overlay (N7) | Not started | | |
| E7 | Medium | Mask and component limits dim their commands (N8) | Not started | | |
| E8 | Medium | View ▸ Play / Pause, Space (N9, I6) | Not started | | |
| E9 | Medium | Video loupe context menu (N9) | Not started | | |
| E10 | Medium | Edit ▸ Deselect All ⇧⌘A, shared item (I5) | Not started | | |
| E11 | Medium | File ▸ Stop ‹job› ⌘., shared item (I4) | Not started | | |
| E12 | High | Export enablement: targets include a photo, no export running (I1) | Not started | | |
| E13 | High | Add Folder Without Copying… always enabled, queues (I2) | Not started | | |
| E14 | High | Export results in Activity only, no alert (I3, D2) | Not started | | |
| E15 | Medium | Suggest Keywords shows Info ▸ Keywords (I7) | Not started | | |
| E16 | Medium | "Caption" becomes "Description" (I8) | Not started | | |
| E17 | Medium | One shared field-label set (I9) | Not started | | |
| E18 | Medium | Delete confirmations for presets (I11) | Not started | | |
| E19 | Low | Reset All Adjustments enablement (I12) | Not started | | |
| E20 | Low | Save Adjustments as Preset… enablement (I13) | Not started | | |
| E21 | Low | RAW+JPEG Pair ▸ for pairs only, with checkmarks (I14) | Not started | | |
| E22 | Low | Toolbar Crop and Original show their on state (I15) | Not started | | |
| E23 | Low | Import Selection pull-down enablement (I16) | Not started | | |
| E24 | Low | Add Folder open panel prompt (I17) | Not started | | |
| E25 | Low | Remove Edit ▸ Find ▸ Clear Filter (I18, D1) | Not started | | |
| E26 | Low | View ▸ Info / Adjust checkmarks (I19) | Not started | | |
| E27 | Low | User guide kept current (I30, RI-5) | In progress | | Each change's guide edits are listed in its row; the two stand-alone fixes (Show Videos, ⌘= / ⌘− in the loupe column) are not started |
| E28 | Medium | Remove the dead Help item (N13, R1, R2) | Not started | | |

## Open questions

### Design questions (apple-ui-designer)

None yet.

### Requirements issues (product-manager)

None yet.
