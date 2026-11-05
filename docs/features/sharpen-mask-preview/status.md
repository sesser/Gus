# Sharpening mask preview: implementation status

Owner: swift-macos-engineer. Implements [`prd.md`](prd.md) (Approved,
2026-11-05) against [`design.md`](design.md) (Designed). Branch
`feature/sharpen-mask-preview`, cut from `develop` at `c436d49`.

States: Not started · In progress · Done · Blocked (waiting on a question
below).

## Build and test

- Baseline at `c436d49` (2026-11-05): `swift build` clean; `swift test` 501
  tests in 91 suites passed, 1 known issue (the `withKnownIssue` in "Live
  render session", pre-existing).

## Plan

Where things live:

- **PhotoCore, rendering.** `AdjustmentRenderer.sharpen` is split so that
  the neighborhood range (`low`, `high`) and the Masking blend mask come
  from one helper each, which both `sharpen` and the map call: the map is
  the same code, not a copy. The Core Image graph `sharpen` builds is
  unchanged (R13; goldens unchanged, no pipeline bump). `downstream` is
  split at the sharpening step (`beforeSharpening`), so the map's input is
  the image the sharpening step sees. New: the image entering sharpening,
  the sharpening mask for given settings and scale (full at Masking 0,
  computed at every scale, including below 0.2), and its display encoding
  (mask *v* shown as the interface's gray *v*).
- **PhotoCore, rules.** `SharpeningMapStatus` (design §7, §11: applied, or
  not applied, and whether masks in effect still sharpen) and
  `SharpeningMapState` (§6: the map suspends the overlay and Show Original
  and gives them back on hide; a value change drops the suspended
  original). Pure values, tested.
- **PhotoCore, live frames.** `LiveRenderSession.render` gains a content
  choice: the photo or the sharpening map. Map frames use the same stage
  cache, drafts and cadence, and carry no histogram; a frame says whether
  it shows the photo, which is what decides the histogram and the preview
  cache (R7).
- **PhotoCore, refine on pause (R6).** A separate actor renders the map
  from a full-resolution decode, scaled to the zoom (the frame size at fit,
  full size when zoomed), caching the full-resolution image entering
  sharpening so that Masking changes only redo the mask. Separate from the
  session so a long first refine never queues live frames behind it.
- **PhotoApp.** `AdjustmentEditor` owns the map state, renders map frames
  instead of photo frames while it is on, schedules the refine after each
  pause and the 0.5 s spinner, and never seeds the cache or the histogram
  from a map frame. The loupe hides mask handles and ignores clicks on
  them; caption badge, VoiceOver value, actions and announcements; Esc.
  Menus read `LibraryMenuState`; the inspector toggle is an `AppKitButton`.
- **Debug script.** `sharpenmap on|off|toggle`; `print` reports the map's
  state, badge and legend.

Order: (1) renderer split and map API with tests; (2) rules, live map
frames and refine with tests; (3) editor and loupe; (4) menus, context
menu, inspector, strings; (5) debug script, bundle checks, user guide.

## Progress

| Step | State | Commit |
|---|---|---|
| 1 Renderer: shared mask code, map API | In progress | |
| 2 Rules, live map frames, refine | Not started | |
| 3 Editor and loupe | Not started | |
| 4 Menus, inspector, strings | Not started | |
| 5 Debug script, bundle checks, guide | Not started | |

## Acceptance criteria and design checks

Filled in as each is verified.

| Item | How | Result |
|---|---|---|
