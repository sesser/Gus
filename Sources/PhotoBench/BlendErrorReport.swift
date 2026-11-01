import CoreImage
import Foundation
import PhotoCore
import PhotoFixtures

/// How far a local adjustment applied as blend(base, adjusted(p), α) is from
/// the module run at α · p, per local control (docs/PHASE6_PLAN.md, decision 5).
///
/// Every test scene, each control at four values across its range, α from 0.1
/// to 0.9. The blend is computed in the working space (linear Rec. 2020), as
/// the renderer blends; differences are measured in the perceptual encoding
/// (sRGB curve, clipped to 0 … 1, as goldens are), so 1/255 is one 8-bit step.
enum BlendErrorReport {
    struct Control {
        var name: String
        var values: [Double]
        var set: @Sendable (inout Adjustments, Double) -> Void
    }

    static let controls: [Control] = [
        Control(name: "exposure", values: [-4, -2, 2, 4]) { $0.exposure.ev = $1 },
        Control(name: "contrast", values: [-100, -50, 50, 100]) { $0.tone.contrast = $1 },
        Control(name: "highlights", values: [-100, -50, 50, 100]) { $0.tone.highlights = $1 },
        Control(name: "shadows", values: [-100, -50, 50, 100]) { $0.tone.shadows = $1 },
        Control(name: "whites", values: [-100, -50, 50, 100]) { $0.tone.whites = $1 },
        Control(name: "blacks", values: [-100, -50, 50, 100]) { $0.tone.blacks = $1 },
        Control(name: "temperature", values: [-100, -50, 50, 100]) { $0.whiteBalance.relativeTemperature = $1 },
        Control(name: "tint", values: [-100, -50, 50, 100]) { $0.whiteBalance.relativeTint = $1 },
        Control(name: "vibrance", values: [-100, -50, 50, 100]) { $0.presence.vibrance = $1 },
        Control(name: "saturation", values: [-100, -50, 50, 100]) { $0.presence.saturation = $1 },
        Control(name: "clarity", values: [-100, -50, 50, 100]) { $0.presence.clarity = $1 },
        Control(name: "dehaze", values: [-100, -50, 50, 100]) { $0.presence.dehaze = $1 },
        Control(name: "sharpen", values: [25, 50, 75, 100]) { $0.sharpen.amount = $1 },
    ]

    static let alphas = (1...9).map { Double($0) / 10 }

    static func run(_ arguments: Arguments) async throws -> [String: any Sendable] {
        let engine = RenderEngine(contextCount: 1, name: "blend-error")
        let renderer = AdjustmentRenderer()
        let scenes = TestScene.allCases.map { ($0, $0.image()) }
        func render(_ adjustments: Adjustments, _ input: LinearImage) -> [Float] {
            let image = renderer.render(adjustments, to: input.ciImage, context: RenderContext())
            var pixels = [Float](repeating: 0, count: input.width * input.height * 4)
            pixels.withUnsafeMutableBytes { buffer in
                engine.withContext {
                    $0.render(image, toBitmap: buffer.baseAddress!, rowBytes: input.width * 16, bounds: input.ciImage.extent,
                              format: .RGBAf, colorSpace: RenderEngine.workingColorSpace)
                }
            }
            return pixels
        }
        func encode(_ value: Float) -> Double {
            let linear = min(max(Double(value), 0), 1)
            return linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
        }

        print("| control | values | max difference | 8-bit steps | mean of per-case maxima | worst case |")
        print("|---|---|---|---|---|---|")
        var report: [String: any Sendable] = [:]
        for control in controls {
            var worst = (difference: 0.0, scene: "", value: 0.0, alpha: 0.0)
            var maxima: [Double] = []
            for (scene, input) in scenes {
                let base = render(.none, input)
                for value in control.values {
                    var full = Adjustments()
                    control.set(&full, value)
                    let adjusted = render(full, input)
                    for alpha in alphas {
                        var scaled = Adjustments()
                        control.set(&scaled, value * alpha)
                        let module = render(scaled, input)
                        var largest = 0.0
                        for i in base.indices where i % 4 != 3 {
                            let blended = base[i] + Float(alpha) * (adjusted[i] - base[i])
                            largest = max(largest, abs(encode(blended) - encode(module[i])))
                        }
                        maxima.append(largest)
                        if largest > worst.difference { worst = (largest, scene.rawValue, value, alpha) }
                    }
                }
            }
            let mean = maxima.reduce(0, +) / Double(max(maxima.count, 1))
            let values = control.values.map { String(format: "%g", $0) }.joined(separator: ", ")
            print("| \(control.name) | \(values) | \(String(format: "%.4f", worst.difference)) | "
                  + "\(String(format: "%.1f", worst.difference * 255)) | \(String(format: "%.4f", mean)) | "
                  + "\(worst.scene), \(String(format: "%g", worst.value)) at α \(String(format: "%g", worst.alpha)) |")
            report[control.name] = ["max": worst.difference, "meanOfMaxima": mean, "scene": worst.scene,
                                    "value": worst.value, "alpha": worst.alpha] as [String: any Sendable]
        }
        return report
    }
}
