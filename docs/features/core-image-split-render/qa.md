# Halves that don't line up at 100% (Core Image split render): QA

Owner: qa-tester. Date: 2026-11-21. Step 4 of `docs/WORKFLOW.md`. Bug fix
(issue #253): checked against the **Bug** section of `status.md` and the issue.
No design review (no UI changed).
Tested: `bug/core-image-split-render` at `25e2b33` (merge base with
`origin/develop`: `9bcac27`), on a MacBook with an Apple M4 Pro, macOS 27.2.1
(26B131), Xcode's macOS 27.2 SDK (Swift 6.4.2). The "develop" side of every
before/after below is `9bcac27` built from `git archive` in a scratch folder.

## Verdict

**Passes**, with two small notes for the engineer's wording (Q1, Q2) and a short
list of eye checks for the owner (P1 to P3). The bug reproduces on `develop` in
the app (4 of 4 zooms with a hard vertical seam, with Highlights -45 and with
Shadows) and is gone on the branch (0 of 8 and 0 of 3 zoom levels, the eight
snapshots byte for byte equal); the regression tests fail without the fix and
pass with it; the full suite, the opt-in large soak and both bundles are green;
no golden moved and `PreviewCacheKey.currentPipelineVersion` is still 13.

I could not bring the scripted app to the front (macOS refused: `frontmost`
stayed false after six tries, as `CLAUDE.md` warns), so the **Z key and the
zoom animation** were not run with a real key window. The 100% rendition was
reached with `zoomstep in` (the same `loadFullResolution` path as `Z`); the
key itself is P1.

## Acceptance criteria

The Bug section has one report, two reproductions and one expected behavior;
each is mapped, plus the claims `status.md` makes around the fix.

| AC | How | Evidence | Result |
|----|-----|----------|--------|
| B1. Step 1, in the app: a 5472 x 3648 16-bit Display P3 TIFF with Highlights -45 (Exposure +1.05, Contrast +66, Blacks -100) at 100%: the photo, the same every time, no seam | Script | Script A: `develop` bundle shows the hard seam at the middle in 4 of 4 zooms (`d2_z1..4`, byte for byte equal); the branch bundle shows none in 8 of 8 (`x1_z1..8`, all one md5), continuous rings and diagonal edge across the middle. Compared by eye on every distinct snapshot | Pass |
| B1b. As B1 with Shadows +70 and Highlights -45, at 100%, 200% and 400% | Script | Script B: `develop` seam at 100%; branch clean at 100%, 200% and 400% (`x2_100/200/400`) | Pass |
| B2. Step 2, headless: a 16 to 48 MP TIFF or PNG with Highlights -45 or Shadows rendered at full size several times on fresh engines: no render with the left half repeating the right | Test | `ImageIOFullDecodeTests.largeRenderKeepsItsParts` ("A full render of a 20 MP TIFF with Highlights keeps its parts in place"), opt-in: `LARGE_RENDER_TESTS=1 swift test --filter ImageIOFullDecodeTests` passes (7 of 7, soak 9.4 s). **Fails without the fix**: copy turned off in a scratch copy, 3 runs, each "1 of 16 renders showed the right half on the left" and `unlike == 0` false (see Mutation checks). PNG is not in the test (same decode path as TIFF); not run separately | Pass |
| B3. Root cause removed: no full-size ImageIO decode is read from the CPU by a split render | Test | `fullDecodeIsResident` (`CIImage.url` is nil for the full-size TIFF and JPEG decode; the measuring decode `forSizeOnly` still reads the header) and `renderUnchanged`'s `decoded.url == nil`: both fail without the fix, ungated, so CI runs them | Pass |
| B4. The second route to the seam, the 100% base for live frames (`LiveRegionRenderer.materialize`), is also right | Test | `LiveRegionRendererTests` "A region is the same area of the full-resolution render": fails when `develop`'s flipped `materialize` is put back with the fix in place (scratch copy); passes on the branch. `SpotTests.everyDecoderHeals` passes | Pass |
| B5. #228's guard still sees what it must (the lazy JPEG decode could show a stale input area; the copy cannot) | Test | `LensAlignStaleAreaTests.tileSeesTheInputArea`: the JPEG case fails without the fix, the blurred-scene case still pins `sees: true`. Read: the case was changed on purpose (code review confirmed) | Pass |
| B6. Unedited renders are as before | Test, Script | `renderUnchanged` (unedited: bit for bit in float; JPEG and 16-bit TIFF). Script C: unedited full-size `photocli render` of the JPEG and TIFF, branch against `develop`: worst 1 level in 8 bits, 0 values more than one level off | Pass |
| B7. Photos over 100 MP or 16384 px a side, no device, a failed copy: fall back to the lazy read with a log notice | Test | `residencyLimit` (both limits, edges, order, `resident` returns nil for 10000 x 10001 with nothing allocated), `bandsCoverTheExtent`, `residentCopyIsTheFile` (several bands, exact in float). The two paths that need no Metal device or a refusing Core Image cannot be reached here (as `status.md` says); read in `ResidentDecode.swift`: both log and return nil | Pass |
| B8. EXIF orientation still applied to the full-size decode | Test | `fullDecodeIsOriented` (floats in the working space, exact) | Pass |
| B9. Fit, thumbnails and previews unchanged | Script, Test | Read: the diff touches only the `longEdge == nil` branch of `decodeWithImageIO`; the thumbnail path returns before it. Script C: `photocli render --long-edge 256 / 1600 / 2560` of JPEG and TIFF, with and without Straighten 2 degrees, branch against `develop`: 10 of 12 byte for byte equal; the other two at 1600 differ by 1 level in at most 6e-6 of values and the same case rerun on both builds was byte for byte equal (run-to-run rounding, not this change). Script A: the Fit canvas of the app is identical pixel for pixel (`d2_fit` against `x1_fit`, canvas cropped; the window's traffic lights differ). `PreviewCacheKey.currentPipelineVersion` is 13 and unchanged (`git diff 9bcac27..HEAD` touches no such file) | Pass |
| B10. "The one render change": full-size renders of a straightened non-raw photo now resample in linear light; a few edge pixels move, no halo | Script, Person | Script C (below). Straighten 2 degrees on a dense synthetic checker: worst 16 (JPEG) to 38 (owner's stack), 0.8 to 2.4% of values more than one level off; viewed as 640 x 360 crops at 2x, branch and `develop` look the same, edges clean, no halo. Same size and frame. **Real photo by eye: P2** | Pass (P2 open for a real photo) |
| B11. No golden moved, no tolerance loosened | Test | Full `swift test` with no goldens touched; `git diff 9bcac27..HEAD --stat` lists no file under `Tests/PhotoCoreTests/Goldens`; `UPDATE_GOLDENS` not run | Pass |
| B12. Builds | Script | `Scripts/build-app.sh all` exit 0 (both bundles); `swift test` full: 1283 tests in 184 suites passed (72.0 s), 0 failures | Pass |
| B13. macOS 15 and macOS 26, whether the fault exists there and the fix holds | Person | Not checked here; CI is the first run (`status.md` "Not verified"). Not asked of the owner (project rule: no checks on macOS 15 or 26) | Open (CI only) |

## Findings

**Q1 (note for `status.md`, not a failure).** "The one render change" says the
export resize was measured at "at most one step". That holds without
Straighten. With Straighten 2 degrees **and** an export to 2048 px (JPEG),
the same dense checker differs from `develop` by up to 22 to 24 levels in 16 to
17% of values (mean 0.73 to 0.76 of a level). The cause is the one already named
(rotation now interpolates linear light, then the resize averages many more
edges), the image looks the same by eye with no halo, and a natural photo has
far fewer hard edges, but the sentence should say "Straighten plus an export
resize" so Ship and the owner read the change right.

**Q2 (note, answers code review Q2 in part).** The unmeasured items were
measured here at full size, branch against `develop`, JPEG and 16-bit TIFF:
Manual Distortion at +30 and -30: worst 1 level, no value more than one off (no
change); Manual Color Alignment (red +20, blue -20): worst 4 levels, 0.03% of
values more than one off, mean 0.24 of a level. So the resampling change is
confined to Straighten and rotation by angle for practical purposes. `status.md`
"Not verified" can drop the Distortion and Color Alignment lines.

No failures. No Design questions or Requirements issues.

Mutation checks, in a scratch copy of the branch (`git archive HEAD`, outside
the checkout; the checkout was never edited and `git status` is clean):

| Change in the scratch copy | Result |
|---|---|
| `let image = lazy` in `decodeWithImageIO` (copy off), run 1: `LARGE_RENDER_TESTS=1 swift test --filter "ImageIOFullDecodeTests|LensAlignStaleAreaTests"` | 7 issues: `fullDecodeIsResident` (2), `renderUnchanged` (2, `decoded.url == nil`), `tileSeesTheInputArea` jpeg, `largeRenderKeepsItsParts` (`swapped == 0`, `unlike == 0`) |
| Same, `largeRenderKeepsItsParts` alone, runs 2 and 3 | each: "1 of 16 renders showed the right half on the left", fails |
| Fix restored, `develop`'s flipped `LiveRegionRenderer.materialize` put back: `swift test --filter "LiveRegionRendererTests|SpotTests"` | `LiveRegionRendererTests` "A region is the same area of the full-resolution render" fails (`result.over == 0`, center, crop and straighten); the other 37 pass |

## Scripts

All runs used a bundle copy with its own identifier
(`me.sesser.gus.debugtest.splitfix` for the branch,
`me.sesser.gus.debugtest.splitdev` for `develop`, each re-signed ad hoc), a
scratch library under the session's scratch folder and `--library-root` on every
launch, started with `open -W -n --stdout <log> <copy> --args ...`. `S` is the
scratch folder. The test file `$S/tiff/big5472.tif` is 5472 x 3648, 16-bit chunky
RGB, uncompressed, Display P3, orientation 1 (written by the generator in the
paste-ready command under "For a person": rings, a 64 px checker and a sharp diagonal edge so a seam and a halo show). The
window was not the key window (`print responder`: `key nil`), as before, and
macOS refused `frontmost` for the process (six tries); `zoomstep in` still
changed the loupe to 100%, 200% and 400% and loaded the full rendition.

**Script A** (owner's stack, 100%; run with the branch copy, then with the
`develop` copy; the document is 2736 points wide, so the seam sits at point
1368, inside the view at 100%, 200% and 400%):

```
windowsize 2200 1300; addfolder $S/tiff; waitimport; focus 0; loupe; wait 2; adjust exposure 1.05; adjust contrast 66; adjust highlights -45; adjust blacks -100; wait 3; print loupe; snapshot $S/shots/<tag>_fit.png
```
then, repeated N times (N = 8 on the branch, 4 on `develop`):
```
zoomstep in; wait 10; print loupe; pan 1500 0; wait 6; print loupe; snapshot $S/shots/<tag>_z<i>.png; zoomstep out; wait 5; print loupe
```
and `quit`. Showed: `print loupe` magnification 0.568 at Fit, 1.000 at 100%
(visible 1980 x 1084 points). `develop`: all four snapshots are one image and show
a hard vertical seam at the middle (the left part is the right part's pixels
again: the diagonal edge and rings repeat); branch: all eight snapshots are one
image (md5 `bce86aae...`) with continuous rings and one diagonal edge.

**Script B** (Shadows and Highlights, three zoom levels, branch and `develop`):
```
windowsize 2200 1300; addfolder $S/tiff; waitimport; focus 0; loupe; wait 2; adjust shadows 70; adjust highlights -45; wait 3; print loupe; zoomstep in; wait 10; print loupe; snapshot $S/shots/<tag>_100.png; zoomstep in; wait 8; print loupe; snapshot $S/shots/<tag>_200.png; zoomstep in; wait 8; print loupe; snapshot $S/shots/<tag>_400.png; zoomstep out; wait 5; zoomstep out; wait 5; zoomstep out; wait 5; print loupe; snapshot $S/shots/<tag>_back.png; quit
```
Showed 0.568, 1.000, 2.000, 4.000, then back to 0.568. `develop` at 100%: the
seam, left and right halves identical in content. Branch at 100%, 200%, 400%:
continuous, no seam, checker and diagonal edge unbroken.

**Script C** (headless, `photocli render` and `export` of the branch build
against `develop`'s, scratch library from `photobench import` for the export;
8-bit difference on a 16-bit PNG, TIFF or JPEG read back; the same JPEG made from
the TIFF with `sips`, quality 92):
```
photocli render <file> --out <png> --original
photocli render <file> --out <png> --set exposure.ev=1.05 --set tone.contrast=66 --set tone.highlights=-45 --set tone.blacks=-100 [--set crop.angle=2] [--long-edge N]
photocli render <file> --out <png> --set lensDistortion.on=true --set lensDistortion.source=manual --set lensDistortion.amount=30
photocli render <file> --out <png> --set colorAlignment.automatic=false --set colorAlignment.red=20 --set colorAlignment.blue=-20
photocli develop --version N --library-root <lib> --set ... --set crop.angle=2
photocli export --version 1 --version 2 --to <dir> --library-root <lib> --settings '{"format":"tiff"}'
photocli export ... --settings '{"format":"jpeg","sizing":"longEdge","edgeLength":2048}'
```
| Case (full size 5472 x 3648 unless noted) | Worst level | Values > 1 level |
|---|---|---|
| Unedited, JPEG and TIFF | 1 | 0 |
| Owner's stack, JPEG and TIFF | 1 | 0 |
| Straighten 2, JPEG | 16 | 2.18% |
| Straighten 2, TIFF | 16 | 0.90% |
| Owner's stack + Straighten 2, JPEG | 38 | 2.44% |
| Owner's stack + Straighten 2, TIFF | 32 | 0.82% |
| Export TIFF, owner's stack + Straighten 2 (JPEG, TIFF) | 38, 32 | 2.44%, 0.82% (same as the renders) |
| Export JPEG 2048 px, same stack (JPEG, TIFF) | 22, 24 | 17.1%, 16.4% (Q1) |
| Manual Distortion +30, -30 (JPEG, TIFF) | 1, 0, 0, 0 | 0 |
| Manual Color Alignment red +20 blue -20 (JPEG, TIFF) | 4, 4 | 0.036%, 0.031% (Q2) |
| `--long-edge 256 / 1600 / 2560`, straightened or not | 0 to 1 | 0 |

Crops of the straightened JPEG render (640 x 360 at 2x) and of the 2048 px export
(500 x 300 at 2x) looked the same on both sides: square checker edges, no halo, no
dark or light fringe.

**Safety.** Every launch carried `--library-root` on a scratch library; no bare
`open`. After the runs no `Gus` or `photocli` process was running, and the owner's
library (`~/Library/Application Support/Gus/Library`) has no file newer than the
start of this session. The owner's preferences were not touched (only the
`...debugtest.split*` identifiers wrote any).

## For a person

Short list. The owner checks by eye; none needs VoiceOver, macOS 15 or macOS 26.
No designer review exists, so there are no M-numbers.

**P1. The seam with the real keyboard and a real mouse (covers AC B1).** The
scripted app never became the key window, so `Z`, the zoom animation and pinch
were not run. Build and run with the command below (it opens the 20 MP test TIFF
in the loupe; the stack is set by hand). In the Adjust tab set Exposure +1.05,
Contrast +66, Highlights -45, Blacks -100 (or only Highlights -45, or Shadows
+70). Press `Z` to go to 100% and back about eight times, and pan with a drag
each time. Look for: a hard vertical line at the middle of the photo where the
left side shows pixels from the right side (rings and the diagonal edge
repeating). There should be none. Then try the same on your own merged TIFF from
#150 if you have it at hand. Repeat once or twice after a long wait: the fault
was timing-dependent (0 of 8 bad in one process, 4 of 12 in the next).

**P2. A real straightened photo, at 100% and exported (covers B10).** Open any
full-size JPEG or TIFF from a real camera, set Straighten about 2 degrees (Crop
tool, or `photocli`), look at 100% on a high-contrast edge (a roof line, a window
frame), and export it once at full size and once at 2048 px. Look for a halo or
dark or light fringe along edges, or a frame that looks different from the old
build; the check is whether anything looks wrong, not a pixel match. To compare
with the old look, run the `develop` bundle the same way (`git archive 9bcac27`
into a scratch folder, `Scripts/build-app.sh`).

**P3. Memory with several large photos (the engineer's "Not verified").** Export
a batch of about 10 large TIFFs or JPEGs (20 MP) in one go with the loupe open
at 100% on one of them, and watch Activity Monitor's memory and GPU memory (or
simply that nothing fails or the Mac does not swap hard). The copy holds 16 bytes
a pixel (320 MB at 20 MP) while a render is in use, two renders at a time. A
failed export or a long stall is the thing to look for. Optional; only if you
have such a batch at hand.

Paste-ready command (zsh; builds the branch, makes the 20 MP test TIFF, copies the
bundle under its own identifier, and opens it on a scratch library with the photo
already in the loupe). It never touches your library or preferences:

```
cd ~/Projects/Gus-split-render && Scripts/build-app.sh && S=$(mktemp -d) && mkdir $S/photos $S/lib && cat > $S/maketiff.swift <<'EOF'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let width = Int(args[2])!, height = Int(args[3])!
let space = CGColorSpace(name: CGColorSpace.displayP3)!
var data = [UInt16](repeating: 0, count: width * height * 4)
for y in 0..<height {
    for x in 0..<width {
        let fx = Double(x) / Double(width), fy = Double(y) / Double(height)
        let dx = Double(x) - Double(width) * 0.3, dy = Double(y) - Double(height) * 0.55
        let ring = 0.5 + 0.5 * sin(sqrt(dx * dx + dy * dy) / 37.0)
        let check = ((x / 64 + y / 64) % 2 == 0) ? 0.75 : 0.15
        let edge = (Double(x) * 0.6 + Double(y)) > Double(height) * 0.9 ? 0.25 : 0.0
        let r = min(1, fx * 0.7 + ring * 0.3 + edge)
        let g = min(1, fy * 0.6 + ring * 0.2 + edge * 0.5)
        let b = min(1, check * 0.5 + (1 - fy) * 0.4 + edge * 0.3)
        let i = (y * width + x) * 4
        data[i] = UInt16(r * 65535); data[i + 1] = UInt16(g * 65535); data[i + 2] = UInt16(b * 65535); data[i + 3] = 65535
    }
}
let provider = CGDataProvider(data: Data(bytes: data, count: data.count * 2) as CFData)!
let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
let image = CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: width * 8,
                    space: space, bitmapInfo: bitmap, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
let url = URL(fileURLWithPath: args[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1]] as CFDictionary)
precondition(CGImageDestinationFinalize(dest))
EOF
swiftc -O $S/maketiff.swift -o $S/maketiff && $S/maketiff $S/photos/big5472.tif 5472 3648 && cp -R build/Gus.app $S/Gus.app && plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.splitcheck $S/Gus.app/Contents/Info.plist && codesign --force --deep --sign - $S/Gus.app && open -n $S/Gus.app --args --library-root $S/lib --debug-script "windowsize 2200 1300; addfolder $S/photos; waitimport; focus 0; loupe"
```

The script ends without `quit`, so the app stays open for you; quit it with ⌘Q
when done. To use your own TIFF instead, copy it into `$S/photos` before the
last line (or run the last line with your folder in place of `$S/photos`).

## Follow-up

Reruns after fixes and the owner's sign-off are recorded here when relayed.
Open: P1, P2, P3 (P3 optional); B13 is CI's.
