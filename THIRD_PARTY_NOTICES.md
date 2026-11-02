# Third-party notices

## LightCraft

Some mask math follows LightCraft (https://github.com/storytold/lightcraft,
commit `07301cb`), licensed under the MIT License or the Apache License,
Version 2.0, at the user's option; it is used here under the MIT License.
Nothing was copied verbatim: the formulas were reimplemented in Swift. Each
place says so in a comment.

- The brush dab profile (1 inside the hard core, 1 − smoothstep beyond it)
  and dabs spaced a quarter of the radius apart:
  `Sources/PhotoCore/Edits/Masks/BrushRasterizer.swift`, from
  `crates/pipeline/src/masks.rs` (`dab_alpha`, `dab_spacing`).
- The color range's weighted OkLab distance √(Δa² + Δb² + ¼ΔL²) and the
  range of its tolerance (0.015 + 0.06 × tolerance / 100):
  `Sources/PhotoCore/Edits/Masks/MaskRenderer.swift`, from
  `crates/pipeline/src/masks.rs` (`shape_alpha`, `color_range_tolerance`).

```
MIT License

Copyright (c) 2026 ArtCraft Team and the LightCraft contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
