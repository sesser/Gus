# Phase 3 plan, first pass: adjustments

Status: **first pass done** (all nine steps). See the end of this file for how
the result differs from the plan, and `docs/PROFILING.md` for measurements.

Design record for the first pass of editing: global adjustments, edited from an
**Adjust** tab in the loupe's right sidebar. The architecture rules in
`CLAUDE.md` still apply; this file records the decisions made for phase 3 and
why.

Out of scope for this pass: brushes and masks, healing, cropping and rotation,
lens corrections, export, ML denoising, Adobe `.dcp` camera profiles, writing
adjustments into XMP sidecars, and editing videos.

## Build order

Each step lands as its own commits, with tests, before the next starts.

1. Engine: typed adjustments over the edit stack, the renderer, auto exposure
   and white balance
2. Live editing in the loupe and the Adjust tab
3. Develop heading
4. Tone heading: curve with histogram
5. Details heading: sharpening and noise reduction
6. Color Grading heading: wheels
7. Look-up tables: browser, import, intensity (revised: collections, Effects heading)
8. Copy/paste adjustments and presets
9. Profiling and docs

## The sidebar

The inspector gets an **Info | Adjust** switch at the top. The loupe opens on
Adjust and the grid on Info; each mode remembers its last choice. Adjust shows
five collapsible headings, each with a reset button:

- **Develop**: profile (RAW), white balance (preset, temperature, tint),
  exposure with Auto, contrast, highlights, shadows, whites, blacks, clarity,
  dehaze, vibrance, saturation.
- **Tone**: a point curve over the histogram, on RGB or on red, green or blue.
- **Details**: sharpening (amount, radius, detail, masking) and noise reduction
  (luminance; color for RAW files).
- **Color Grading**: shadows, midtones and highlights wheels (hue, amount,
  luminance), balance and blending.
- **Effects**: look-up table (a menu of collections, intensity, color space,
  Browse/Import/Manage), vignette (amount, size, roundness) and grain
  (strength, amount for shadows, midtones and highlights, roughness, color,
  size).

Each group of controls (Profile, White Balance, Light, Presence, Tone Curve,
Sharpening, Noise Reduction, Color Grading, Look-Up Table, Vignette, Grain)
has a round check box, in its caption or, for single-group headings, in the
heading. It checks itself when the group has edits; unchecking it turns the
group's edits off without losing them (its controls fade), so the photo can be
compared with and without them. Changing a control of a group that is off
turns it back on. Each toggle is an undo step.

Double-clicking a slider resets it. `\` shows the original while editing.
Edits apply to the focused photo only; copy/paste and presets reach the
selection. Videos have no Adjust tab content.

## Edit stack

`Adjustments` (in `PhotoCore/Edits`) is a typed view of a version's
`EditStack`. Each module is one operation with a generic, persisted kind:

| kind | parameters |
|---|---|
| `rawDecode` | `look` (standard, neutral, flat), `decoderVersion` |
| `whiteBalance` | `preset`, `temperature` (K), `tint` (RAW); `relativeTemperature`, `relativeTint` (other files) |
| `exposure` | `ev` |
| `tone` | `contrast`, `highlights`, `shadows`, `whites`, `blacks` |
| `presence` | `clarity`, `dehaze`, `vibrance`, `saturation` |
| `toneCurve` | `rgb`, `red`, `green`, `blue`: flat `[x0, y0, x1, y1, …]` lists |
| `colorGrade` | `<range>Hue`, `<range>Amount`, `<range>Luminance` for shadows, midtones, highlights; `balance`, `blending` |
| `lookTable` | `identifier` (SHA-256 of the file), `name`, `intensity`, `colorSpace` (`sRGB`, `displayP3`, `adobeRGB`, `proPhoto`) |
| `vignette` | `amount`, `size`, `roundness` |
| `noiseReduction` | `luminance`, `color` |
| `sharpen` | `amount`, `radius`, `detail`, `masking` |
| `grain` | `strength`, `shadows`, `midtones`, `highlights`, `roughness`, `color`, `size` |

Modules and parameters at their defaults are left out, so resetting everything
gives back `EditStack.identity` and shares the original's cached previews.
A group that is turned off keeps its operations with `isEnabled` false:
`Adjustments.disabled` records them and `effective` (what renders, what the
decoder gets) puts them at their defaults. Disabled operations are not in the
render hash, so turning a group off shares the cached previews of the edit
without it. Operations of unknown kinds or newer kind versions are kept and
written back unchanged. All kinds are `kindVersion` 1.

## Rendering

`AdjustmentRenderer` replaces `PassThroughRenderer` as the default. The order is
fixed whatever the order of operations: decode, white balance (non-RAW),
exposure, highlights/shadows, dehaze, clarity, the tone table, vibrance and
saturation, color grading, look-up table, vignette, noise reduction (non-RAW),
sharpening, grain.

- **Decode settings** (white balance, look, decoder version, noise reduction
  for RAW files) go to `CIRAWFilter` before demosaicing. Only values that are
  set are applied, so an identity stack decodes exactly as in phase 2 and the
  pipeline version does not change.
- **Built-in filters only**: SwiftPM has no Metal build step and the string
  kernel API is deprecated. Exposure is `CIExposureAdjust` in linear light;
  shadows and negative highlights a local gain (below); contrast, whites,
  blacks, positive highlights and the curves fold into one table per channel for
  `CIColorCurves`, in Rec. 2020 with the sRGB transfer curve, over 0 … 2 so
  values above white pass through; color grading is a generated 33³ cube.
- **Clarity** is a large-radius unsharp mask whose radius follows the image
  size, so every tier looks the same. **Dehaze** subtracts a veil estimated
  from the darkest level of a 64 px copy (lazily, inside the graph), plus a
  little contrast and saturation.
- **Sharpening** radius is given at full resolution and scaled to the decode;
  it is skipped below a fifth of full size (grid thumbnails). Low Detail holds
  the sharpened value inside each pixel's 3×3 range (no halos); Masking limits
  it to edges. The decoder's own sharpening stays at its default.
- **Profiles** are our own looks built from the decoder's boost: Standard (its
  default), Neutral (half boost), Flat (none), plus a choice of decoder version
  where the camera has several.
- **HDR**: renditions keep values above white for exposure, white balance,
  profile, noise reduction, sharpening, saturation and clarity. While the tone
  table, grading cube, a look-up table or grain is active the loupe shows SDR.
- **Vignette** is an exposure falloff (up to two stops) multiplied in linear
  light: an ellipse through the corners with the frame's proportions, blended
  toward a circle (positive roundness) or toward the frame's rectangle
  (negative). It keeps HDR.
- **Grain** is `CIRandomGenerator` noise grown to the grain size (about 1/2400
  of the long edge at size 1, so every tier shows the same grain relative to
  the frame; below a pixel it is drawn weaker), mixed with a coarser octave and
  softened as roughness drops, monochrome mixed with per-channel noise by
  Color, weighted by a luminance table from the three tonal amounts, and added
  with a linear-light blend in the sRGB encoding. The generator is
  deterministic, so renders are reproducible.
- **Auto** exposure and white balance measure a 256 px render and write plain
  numbers: exposure aims the geometric mean at mid grey, held back by at most a
  stop to keep the brightest 0.5 % below white; white balance solves for a grey
  average with Newton steps (Kelvin and tint for RAW, relative shifts otherwise).

## Look-up tables

`.cube` files (3-D up to 65³, 1-D, `DOMAIN_MIN/MAX`, `TITLE`) live in
collections: a built-in one (a few looks generated in code as `.cube` text,
see `BuiltInLookTables`) and the ones the person imports. Collections are flat
(no nesting). Every table file is copied into `Library/LUTs/<sha256>.cube`, so
edits keep rendering when the source folder moves, and removing a table or a
collection from the library never deletes its file.

- **Import** reads a folder (or files), names each table from its header (a
  `TITLE`, a `# Title:`/`# Name:` comment, or a short first-line comment that
  is not a tool's credit) or else from its file name (separators as spaces,
  a prefix every file shares removed, all-lowercase names capitalized), and
  adds it to a new collection or an existing one, with a color space for the
  batch. Names can be changed before importing.
- **Browse** opens the Look-Up Tables window: a collection pop-up (or all),
  one pane per collection, only the first expanded; only expanded panes render
  previews, on a 360 px copy of the photo with its saved adjustments and no
  effects. Click picks, Apply or a double-click applies.
- **Manage** renames collections and tables, changes a table's default color
  space, and removes tables and collections.
- **Color space**: each table is applied in its color space (sRGB by default;
  Display P3, Adobe RGB or ProPhoto RGB for tables made for them). Applying
  takes the table's default; the Adjust tab changes it per photo.

## Catalog changes

Migration `v8`: `adjustmentPreset` (`uuid`, `name`, `settings` as edit stack
JSON, `createdAt`). Edits are not synced to XMP sidecars.

Migration `v10`: `lookTableCollection` (`uuid`, `name`, `createdAt`) and
`lookTableEntry` (`collectionId`, `identifier`, `name`, `colorSpace`,
`fileName`, `position`, `createdAt`; unique per collection and identifier).

## As built

Where the implementation settled details the plan left open, or differs:

- **Commits**: steps 2 and 3 (live editing and the Develop heading) landed
  together; the others each have their own.
- **Live frames** are rendered at the preview tier's size (2560 px). Zoomed to
  1:1 the loupe shows the live frame while a slider moves and the
  full-resolution render of the saved edit once the gesture ends, rather than
  rendering the visible rectangle live.
- **Cached renditions** of intermediate edits are deleted when the photo
  closes in the loupe (all but the saved edit and the original); undoing past
  them regenerates from the master.
- **Highlights/shadows**: shadows and negative highlights are a gain per
  pixel (`LocalToneCurve`, in stops around mid grey) looked up from a smoothed
  luminance: a 256 px copy of luminance to the power ¼, brought back to full
  size with `CIEdgePreserveUpsample` guided by the image, so tones move by
  region without halos at strong edges and local detail is kept. Recovery
  lowers the slope above a knee a stop over mid grey, so two stops over white
  come back below it; shadows lift by at most three stops. With negative
  highlights or exposure, RAW files are decoded with extended range so there
  is something above white to recover. Positive highlights stay in the tone
  table. (The first version used `CIHighlightShadowAdjust`, which was too weak.)
- **Info tab**: histogram (live while the loupe edits the photo, otherwise
  from its cached thumbnail), camera and lens, two rows of tiles (shutter,
  aperture, ISO; exposure compensation, 35 mm equivalent focal length, flash
  with its compensation, faint at 0 EV or when the flash did not fire), size,
  capture date, file name and folder, then keywords. Flash compensation comes
  from maker notes: migration `v9` adds `image.flashCompensation`, and
  `ImageMetadata.revision` 4 makes existing masters be read again.
  Revision 5 names lenses that only maker notes identify (Panasonic, older
  bodies) from ExifTool's `LensID`, which is read printed while every other
  tag is read as a raw number, and fills in a missing lens on existing masters.
- **Auto white balance** is a preset entry rather than a button: picking Auto
  measures once and stores the result as plain numbers.
- **Look-up table previews** render the photo with its saved adjustments and
  without its own table, from the live session, whenever the saved edit changes.
- **Debug script**: `adjust …` (including `adjust off|on <group>`), `original`,
  `tab`, `lut`, `lutimport`, `luts`, `lutwindow …`, `scroll`, `copyadjust`,
  `pasteadjust`, `preset` and `print adjustments` drive all of it.
