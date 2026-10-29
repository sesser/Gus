# Phase 4 plan, first pass: export

Status: **first pass done**. Tracks issue #6 (Basic Export Functionality - Phase 1).

Design record for the first export: **File ▸ Export…** (⇧⌘E) writes the
selected photos, rendered with their adjustments, to one folder. The
architecture rules in `CLAUDE.md` still apply; this file records the decisions
made for export and why.

Out of scope for this pass: DNG output, exporting originals or videos, more
than one destination per export, export to services, and watermarks with text.

## Decisions

- **What is exported.** The library's action targets (the grid selection, or
  the photo in the loupe). A RAW+JPEG pair exports once, rendered from its
  RAW, whichever half is selected (`ExportTargets.resolve`). Videos are left
  out and counted. The RAW's own edits are used: edits are per file.
- **Rendering.** `PreviewGenerator.image(longEdge: nil)` renders the master
  through its edit stack at full resolution. Resizing comes after the edits, so
  radii and grain stay true to the full-size photo. Then, in order: Lanczos
  resize (edges clamped so borders do not darken), output sharpening, the
  watermark. Output goes through the one `CIContext` to an 8- or 16-bit RGBA
  `CGImage` in the chosen color space (sRGB by default, Display P3, Adobe RGB
  (1998) or ProPhoto RGB). The image is never enlarged.
- **Formats.** JPEG with a quality setting, and TIFF at 8 or 16 bits with no
  compression, LZW or ZIP (deflate). We checked that ImageIO honours all three
  TIFF compressions, 16-bit output, embedded profiles and DPI. ImageIO
  cannot write DNG (it is not among `CGImageDestinationCopyTypeIdentifiers`),
  so DNG needs a writer of our own and is left for a later pass.
- **Sizing.** Full size, fit within a box, long edge, short edge or a
  percentage (`ExportSizing`). Pixels per inch go into the file's resolution
  tags and change only the print size.
- **Output sharpening.** Only when the export is smaller than the render. It
  uses the edit stack's unsharp mask (`AdjustmentRenderer.sharpen`) at the
  output size: light, standard or strong, for screen (fixed small radius) or
  print (radius grows with the resolution).
- **Metadata** (`ExportMetadata`). Camera and capture fields come from the
  master's ImageIO properties. The descriptive fields come from the library,
  which is their source of truth: creator, copyright, usage terms, contact,
  caption and keywords. They go into TIFF, IPTC and an XMP packet built with
  `XMPDocument`; ImageIO merges the packet with the properties in one write.
  The modes:
  - **All metadata**: everything above.
  - **All except location**: drops GPS and the IPTC place fields.
  - **Copyright and contact only**: creator, copyright, usage terms and contact.
  - **None**: only the profile, orientation and resolution.

  Rating, flag and color label are never written. Orientation is always 1,
  since the pixels are already upright.
- **Names** (`ExportNaming`). The original name, or a template with the import
  tokens plus `{export:<pattern>}`. `{seq:N}` counts within the export. The
  extension is always the output format's. Names are worked out for the whole
  batch before anything is written. Names inside the batch never collide
  (`-2`, `-3`…, ignoring case). When names already exist in the folder, the
  window asks once, before starting: keep both (numbered names), replace, or
  skip.
- **Writing.** Each file is written to a hidden temporary name next to its
  target, then moved into place (replaced, when overwriting). A file appears
  complete or not at all.
- **Watermark.** One PNG, copied into `Library/Watermarks/<sha256>.png`, as
  look-up tables are, so presets keep working after the original file moves.
  It is placed by one of nine anchors, a margin and a size (both in percent of
  the image's long edge), with an opacity. It is shrunk to fit inside the
  margins. `WatermarkLayout` is shared by the export and the window's preview,
  so the preview shows what is written.
- **Presets.** `exportPreset` table (migration v12): name and `ExportSettings`
  JSON. Every field decodes with a default, so presets from older builds keep
  working. The last settings used, the destination and "Show in Finder" are
  kept in user defaults (`export.*`).
- **Running.** The window closes when the export starts. `ExportJob` renders at
  most two images at once, since a full-resolution RAW in the working format
  is large. The status bar shows progress and a stop button. When the export
  ends, the status bar says how many files were written. An alert lists
  failures (offline volume, unreadable original, missing watermark, write
  error) and skipped files. The Finder can show the written files.

## Code

- `Sources/PhotoCore/Export/`: `ExportSettings` (with `Watermark`),
  `ExportGeometry` (sizing, watermark layout, resize), `ExportNaming`,
  `ExportMetadata`, `ExportRenderer` (render and write), `ExportJob`,
  `ExportPresets` (presets and `ExportTargets`), `WatermarkStore`.
- `Sources/PhotoUI/TemplateField.swift`: the template field and its token
  lists, shared by import and export.
- `Sources/PhotoApp/Model/ExportModel.swift`, `Views/ExportWindow.swift`,
  `Model/DebugExportCommands.swift`.
- Tests: `Tests/PhotoCoreTests/ExportTests.swift`.

## Debug script

`export window | windowshot <png> | set <key>=<value>… | template <text> |
run [keepboth|overwrite|skip] | preset save|apply|delete <name> | print`.
See `DebugExportCommands.swift` for the settings keys.
