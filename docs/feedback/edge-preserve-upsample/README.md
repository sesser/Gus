# Feedback: CIEdgePreserveUpsampleFilter's edge pixels depend on the region rendered (macOS 26)

For Feedback Assistant: Developer Technologies & SDKs ▸ macOS ▸ Core Image.
Attach `repro.swift`. The project's test that found it is
`LiveSessionTests.aboveWhite` (finding 6 in `docs/PHASE6_PLAN.md`).

## Title

CIEdgePreserveUpsampleFilter output at the image edge changes with the
render bounds on macOS 26

## Description

`CIEdgePreserveUpsampleFilter` (guide image 640 × 480, small image from
`CILanczosScaleTransform` at 0.4, spatial sigma 3, luma sigma 0.12) gives
different values at the image's edge depending on the region that is
rendered. The repro renders it in two ways, in one Metal `CIContext`
(working space extended linear Rec. 2020, working format RGBAh):

- A: the filter's output over its own extent.
- B: the same output, `clampedToExtent()`, cropped to 32 pixels more on
  every side and rendered over that larger rectangle.

Inside the extent, A and B should be identical: they are the same pixels
of the same image. On macOS 15 and 27 they are identical. On macOS 26
they differ at the bottom-right corner.

This matters because any filter that reads past an image's edge (a
Gaussian blur on a clamped image, for example) makes Core Image render
the upsample over a larger region. A blur over the upsample then gives a
different result than a blur over the same upsample rendered first, so
results depend on how the graph is split into renders.

## Steps to reproduce

1. On macOS 26, run `swift repro.swift`.
2. Read the "Largest difference" line. The script exits 1 when A and B
   differ.

## Expected

```
Largest difference inside the extent: 0.0 at column 0, row 0 from the top
not reproduced
```

This is the output on macOS 15.8.2 and macOS 27.2.

## Actual (macOS 26.6.2)

```
Largest difference inside the extent: 0.00383538 at column 639, row 479 from the top
  rendered over its extent: 0.5493598
  clamped, rendered wider:  0.5531952
REPRODUCED
```

## Configuration

- Reproduced: macOS 26.6.2 (25G83) on the GitHub Actions `macos-26` runner
  (Apple Paravirtual device).
- Not reproduced: macOS 15.8.2 (24H232) on the `macos-15` runner (Apple
  Paravirtual device), and macOS 27.2 (26B123) on an Apple M4 Pro.
- Not tried: macOS 26 on physical Apple silicon.
