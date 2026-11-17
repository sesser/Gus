/// The Metal source of the demosaic kernels (`GPUDemosaic`), compiled at
/// run time in the safe math mode with floating-point contraction off, so
/// that each kernel does the same operations in the same order as its CPU
/// reference (`Tests/PhotoCoreTests/Reference/DemosaicReference.swift`) and
/// the two can be compared with a bound derived from float rounding
/// (CLAUDE.md, "Checking image code").
///
/// Every kernel reads the sensor's 16-bit values and normalizes them as it
/// reads (`sample`: the site's black taken off, clipped to the white span,
/// times the site's multiplier over the span), so no normalized copy of the
/// mosaic is kept. Coordinates outside the image are mirrored (reflect-101).
///
/// - Bayer (`bayerGreen`, `bayerColor`): green by Hamilton and Adams'
///   directional estimates (US patent 5,629,734), blended by inverse squared
///   gradients (after Pekkucuksen and Altunbasak, "Gradient based threshold
///   free color filter array interpolation", ICIP 2010, with two
///   directions), then red and blue by bilinear interpolation of the color
///   differences against that green (Gunturk et al., "Demosaicking: color
///   filter array interpolation", IEEE Signal Processing Magazine 2005).
///   Written for the #194 spike, where it matched LibRaw's AHD against a
///   known truth.
/// - X-Trans (`xtransGreen`, `xtransColor`): the method of
///   `DemosaicTables`, driven by its tables. Within `border` pixels of an
///   edge, where the mirrored samples no longer follow the pattern, each
///   color is the mean of its samples in the 3 x 3 window (5 x 5 if none).
/// - `binHalf`: a half-size image, each color the mean of its sites in a
///   window around each 2 x 2 block (2 x 2 for Bayer, 4 x 4 for X-Trans).
enum DemosaicKernels {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    #pragma clang fp contract(off)

    struct Params {
        uint width;
        uint height;
        uint period;
        uint border;
        float epsilon;
        float span;
        int binLow;
        int binHigh;
    };
    struct Tap { int dx; int dy; float weight; };
    struct Pair { int ax; int ay; int bx; int by; float weight; };

    inline int mirror(int i, int n) {
        if (i < 0) i = -i;
        if (i >= n) i = 2 * n - 2 - i;
        return clamp(i, 0, n - 1);
    }

    inline uint siteOf(constant Params &p, int x, int y) {
        return (uint(y) % p.period) * p.period + uint(x) % p.period;
    }

    // The normalized value at a pixel inside the image.
    inline float valueAt(device const ushort *raw, constant Params &p, constant float *black,
                         constant float *scale, int x, int y) {
        uint site = siteOf(p, x, y);
        float v = float(raw[uint(y) * p.width + uint(x)]) - black[site];
        return min(max(v, 0.0f), p.span) * scale[site];
    }

    // The normalized value at any pixel, mirrored into the image.
    inline float sample(device const ushort *raw, constant Params &p, constant float *black,
                        constant float *scale, int x, int y) {
        return valueAt(raw, p, black, scale, mirror(x, int(p.width)), mirror(y, int(p.height)));
    }

    // The mean of a color's samples in the 3 x 3 window (the center left out), 5 x 5 when it has none;
    // the pixel's own value for its own color. Colors are those of the mirrored places.
    inline float windowMean(device const ushort *raw, constant Params &p, constant int *pattern,
                            constant float *black, constant float *scale, int x, int y, int c) {
        int w = int(p.width), h = int(p.height);
        if (pattern[siteOf(p, x, y)] == c) return valueAt(raw, p, black, scale, x, y);
        float sum = 0.0f;
        float count = 0.0f;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                if (dx == 0 && dy == 0) continue;
                int mx = mirror(x + dx, w), my = mirror(y + dy, h);
                if (pattern[siteOf(p, mx, my)] != c) continue;
                sum = sum + valueAt(raw, p, black, scale, mx, my);
                count = count + 1.0f;
            }
        }
        if (count > 0.0f) return sum / count;
        for (int dy = -2; dy <= 2; dy++) {
            for (int dx = -2; dx <= 2; dx++) {
                if (abs(dx) < 2 && abs(dy) < 2) continue;
                int mx = mirror(x + dx, w), my = mirror(y + dy, h);
                if (pattern[siteOf(p, mx, my)] != c) continue;
                sum = sum + valueAt(raw, p, black, scale, mx, my);
                count = count + 1.0f;
            }
        }
        return count > 0.0f ? sum / count : 0.0f;
    }

    inline bool inBorder(constant Params &p, int x, int y) {
        int b = int(p.border);
        return x < b || y < b || x >= int(p.width) - b || y >= int(p.height) - b;
    }

    // MARK: X-Trans

    kernel void xtransGreen(device const ushort *raw [[buffer(0)]], constant Params &p [[buffer(1)]],
                            constant int *pattern [[buffer(2)]], constant float *black [[buffer(3)]],
                            constant float *scale [[buffer(4)]],
                            device const uint *tapCounts [[buffer(5)]], device const Tap *taps [[buffer(6)]],
                            device const uint *pairCounts [[buffer(7)]], device const Pair *pairs [[buffer(8)]],
                            texture2d<float, access::write> green [[texture(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
        int x = int(gid.x), y = int(gid.y);
        if (gid.x >= p.width || gid.y >= p.height) return;
        uint site = siteOf(p, x, y);
        if (pattern[site] == 1) { green.write(float4(valueAt(raw, p, black, scale, x, y), 0, 0, 0), gid); return; }
        if (inBorder(p, x, y)) {
            green.write(float4(windowMean(raw, p, pattern, black, scale, x, y, 1), 0, 0, 0), gid);
            return;
        }
        float num = 0.0f;
        float den = 0.0f;
        for (uint d = 0; d < 4; d++) {
            uint n = tapCounts[site * 4 + d];
            if (n == 0) continue;
            float g = 0.0f;
            for (uint i = 0; i < n; i++) {
                Tap t = taps[(site * 4 + d) * \(DemosaicTables.maximumTaps) + i];
                g = g + t.weight * valueAt(raw, p, black, scale, x + t.dx, y + t.dy);
            }
            float v = 0.0f;
            uint m = pairCounts[site * 4 + d];
            for (uint i = 0; i < m; i++) {
                Pair q = pairs[(site * 4 + d) * \(DemosaicTables.maximumPairs) + i];
                v = v + q.weight * abs(valueAt(raw, p, black, scale, x + q.ax, y + q.ay)
                                       - valueAt(raw, p, black, scale, x + q.bx, y + q.by));
            }
            float e = p.epsilon + v;
            float weight = 1.0f / (e * e);
            num = num + weight * g;
            den = den + weight;
        }
        green.write(float4(max(num / den, 0.0f), 0, 0, 0), gid);
    }

    kernel void xtransColor(device const ushort *raw [[buffer(0)]], constant Params &p [[buffer(1)]],
                            constant int *pattern [[buffer(2)]], constant float *black [[buffer(3)]],
                            constant float *scale [[buffer(4)]],
                            device const uint *neighbourCounts [[buffer(5)]], device const Tap *neighbours [[buffer(6)]],
                            texture2d<float, access::read> green [[texture(0)]],
                            texture2d<float, access::write> out [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
        int x = int(gid.x), y = int(gid.y);
        if (gid.x >= p.width || gid.y >= p.height) return;
        uint site = siteOf(p, x, y);
        int own = pattern[site];
        float g = green.read(gid).r;
        float rgb[3];
        rgb[1] = g;
        bool border = inBorder(p, x, y);
        for (int c = 0; c < 3; c += 2) {
            if (c == own) { rgb[c] = valueAt(raw, p, black, scale, x, y); continue; }
            if (border) { rgb[c] = windowMean(raw, p, pattern, black, scale, x, y, c); continue; }
            uint n = neighbourCounts[site * 3 + uint(c)];
            float num = 0.0f;
            float den = 0.0f;
            for (uint i = 0; i < n; i++) {
                Tap t = neighbours[(site * 3 + uint(c)) * \(DemosaicTables.maximumNeighbours) + i];
                int qx = x + t.dx, qy = y + t.dy;
                float gq = green.read(uint2(qx, qy)).r;
                float k = gq - valueAt(raw, p, black, scale, qx, qy);
                float e = p.epsilon + abs(gq - g);
                float weight = t.weight / (e * e);
                num = num + weight * k;
                den = den + weight;
            }
            rgb[c] = max(g - num / den, 0.0f);
        }
        out.write(float4(rgb[0], rgb[1], rgb[2], 1.0f), gid);
    }

    // MARK: Bayer

    kernel void bayerGreen(device const ushort *raw [[buffer(0)]], constant Params &p [[buffer(1)]],
                           constant int *pattern [[buffer(2)]], constant float *black [[buffer(3)]],
                           constant float *scale [[buffer(4)]],
                           texture2d<float, access::write> green [[texture(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
        int x = int(gid.x), y = int(gid.y);
        if (gid.x >= p.width || gid.y >= p.height) return;
        float c0 = sample(raw, p, black, scale, x, y);
        if (pattern[siteOf(p, x, y)] == 1) { green.write(float4(c0, 0, 0, 0), gid); return; }
        float gl = sample(raw, p, black, scale, x - 1, y), gr = sample(raw, p, black, scale, x + 1, y);
        float gu = sample(raw, p, black, scale, x, y - 1), gd = sample(raw, p, black, scale, x, y + 1);
        float lapH = (2.0f * c0 - sample(raw, p, black, scale, x - 2, y)) - sample(raw, p, black, scale, x + 2, y);
        float lapV = (2.0f * c0 - sample(raw, p, black, scale, x, y - 2)) - sample(raw, p, black, scale, x, y + 2);
        float gh = (gl + gr) * 0.5f + lapH * 0.25f;
        float gv = (gu + gd) * 0.5f + lapV * 0.25f;
        float dh = p.epsilon + (abs(gl - gr) + abs(lapH));
        float dv = p.epsilon + (abs(gu - gd) + abs(lapV));
        float wh = 1.0f / (dh * dh), wv = 1.0f / (dv * dv);
        float g = (wh * gh + wv * gv) / (wh + wv);
        green.write(float4(max(g, 0.0f), 0, 0, 0), gid);
    }

    inline float greenAt(texture2d<float, access::read> green, int x, int y, int w, int h) {
        return green.read(uint2(mirror(x, w), mirror(y, h))).r;
    }

    kernel void bayerColor(device const ushort *raw [[buffer(0)]], constant Params &p [[buffer(1)]],
                           constant int *pattern [[buffer(2)]], constant float *black [[buffer(3)]],
                           constant float *scale [[buffer(4)]],
                           texture2d<float, access::read> green [[texture(0)]],
                           texture2d<float, access::write> out [[texture(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
        int x = int(gid.x), y = int(gid.y);
        int w = int(p.width), h = int(p.height);
        if (gid.x >= p.width || gid.y >= p.height) return;
        float g = greenAt(green, x, y, w, h);
        int own = pattern[siteOf(p, x, y)];
        float rgb[3];
        rgb[1] = g;
        if (own == 1) {
            int across = pattern[siteOf(p, mirror(x + 1, w), y)];
            float horizontal = ((sample(raw, p, black, scale, x - 1, y) - greenAt(green, x - 1, y, w, h))
                                + (sample(raw, p, black, scale, x + 1, y) - greenAt(green, x + 1, y, w, h))) * 0.5f;
            float vertical = ((sample(raw, p, black, scale, x, y - 1) - greenAt(green, x, y - 1, w, h))
                              + (sample(raw, p, black, scale, x, y + 1) - greenAt(green, x, y + 1, w, h))) * 0.5f;
            rgb[across] = g + horizontal;
            rgb[2 - across] = g + vertical;
        } else {
            float a = sample(raw, p, black, scale, x - 1, y - 1) - greenAt(green, x - 1, y - 1, w, h);
            float b = sample(raw, p, black, scale, x + 1, y - 1) - greenAt(green, x + 1, y - 1, w, h);
            float c = sample(raw, p, black, scale, x - 1, y + 1) - greenAt(green, x - 1, y + 1, w, h);
            float d = sample(raw, p, black, scale, x + 1, y + 1) - greenAt(green, x + 1, y + 1, w, h);
            float diagonal = (((a + b) + c) + d) * 0.25f;
            rgb[own] = sample(raw, p, black, scale, x, y);
            rgb[2 - own] = g + diagonal;
        }
        out.write(float4(max(rgb[0], 0.0f), max(rgb[1], 0.0f), max(rgb[2], 0.0f), 1.0f), gid);
    }

    // MARK: Half size

    kernel void binHalf(device const ushort *raw [[buffer(0)]], constant Params &p [[buffer(1)]],
                        constant int *pattern [[buffer(2)]], constant float *black [[buffer(3)]],
                        constant float *scale [[buffer(4)]],
                        texture2d<float, access::write> out [[texture(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
        int w = int(p.width), h = int(p.height);
        if (gid.x >= p.width / 2 || gid.y >= p.height / 2) return;
        int ox = int(gid.x) * 2, oy = int(gid.y) * 2;
        float sum[3] = {0.0f, 0.0f, 0.0f};
        float count[3] = {0.0f, 0.0f, 0.0f};
        for (int dy = p.binLow; dy <= p.binHigh; dy++) {
            for (int dx = p.binLow; dx <= p.binHigh; dx++) {
                int mx = mirror(ox + dx, w), my = mirror(oy + dy, h);
                int c = pattern[siteOf(p, mx, my)];
                sum[c] = sum[c] + valueAt(raw, p, black, scale, mx, my);
                count[c] = count[c] + 1.0f;
            }
        }
        float rgb[3];
        for (int c = 0; c < 3; c++) {
            // A window at the edge, mirrored, can miss a color: its 3 x 3 (or 5 x 5) mean instead.
            rgb[c] = count[c] > 0.0f ? sum[c] / count[c] : windowMean(raw, p, pattern, black, scale, ox, oy, c);
        }
        out.write(float4(rgb[0], rgb[1], rgb[2], 1.0f), gid);
    }
    // MARK: Color noise reduction

    struct DenoiseParams {
        uint width;
        uint height;
        int inTop;
        int inRows;
        int outTop;
        int rowBegin;
        int rowEnd;
        int step;
        float hY2;
        float hC2;
        float floor;
        float aR; float aG; float aB;
        float bR; float bG; float bB;
    };

    // One level of the edge-avoiding smoothing of the color differences: a 5 x 5 B3-spline
    // window `step` pixels apart, each neighbour weighted down by its luminance and color
    // difference from the center over what noise would make them differ. Luminance, the
    // center's (R + 2G + B) / 4, is kept.
    kernel void denoise(texture2d<float, access::read> src [[texture(0)]],
                        texture2d<float, access::write> dst [[texture(1)]],
                        constant DenoiseParams &p [[buffer(0)]], constant float *taps [[buffer(1)]],
                        uint2 gid [[thread_position_in_grid]]) {
        int x = int(gid.x), y = p.rowBegin + int(gid.y);
        int w = int(p.width), h = int(p.height);
        if (x >= w || y >= p.rowEnd) return;
        float4 c0 = src.read(uint2(x, y - p.inTop));
        float y0 = ((c0.r + 2.0f * c0.g) + c0.b) * 0.25f;
        float k1 = c0.r - c0.g, k2 = c0.b - c0.g;
        float vr = max(p.aR * max(c0.r, 0.0f) + p.bR, p.floor);
        float vg = max(p.aG * max(c0.g, 0.0f) + p.bG, p.floor);
        float vb = max(p.aB * max(c0.b, 0.0f) + p.bB, p.floor);
        float vy = ((vr + 4.0f * vg) + vb) * 0.0625f;
        float iy = 1.0f / ((2.0f * vy) * p.hY2);
        float i1 = 1.0f / ((2.0f * (vr + vg)) * p.hC2);
        float i2 = 1.0f / ((2.0f * (vb + vg)) * p.hC2);
        float n1 = 0.0f, n2 = 0.0f, den = 0.0f;
        int lowest = p.inTop, highest = p.inTop + p.inRows - 1;
        for (int dy = -2; dy <= 2; dy++) {
            int qy = clamp(mirror(y + dy * p.step, h), lowest, highest);
            for (int dx = -2; dx <= 2; dx++) {
                int qx = mirror(x + dx * p.step, w);
                float4 q = src.read(uint2(qx, qy - p.inTop));
                float yq = ((q.r + 2.0f * q.g) + q.b) * 0.25f;
                float q1 = q.r - q.g, q2 = q.b - q.g;
                float dl = yq - y0;
                float d1 = q1 - k1, d2 = q2 - k2;
                float ry = 1.0f + (dl * dl) * iy;
                float rc = 1.0f + ((d1 * d1) * i1 + (d2 * d2) * i2);
                float weight = (taps[dy + 2] * taps[dx + 2]) / ((ry * ry) * (rc * rc));
                n1 = n1 + weight * q1;
                n2 = n2 + weight * q2;
                den = den + weight;
            }
        }
        float c1 = n1 / den, c2 = n2 / den;
        float g = y0 - (c1 + c2) * 0.25f;
        dst.write(float4(max(g + c1, 0.0f), max(g, 0.0f), max(g + c2, 0.0f), 1.0f), uint2(x, y - p.outTop));
    }
    """
}
