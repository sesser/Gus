import Foundation
import Testing
@testable import PhotoCore

/// AC4: each mapped tool against values derived from the owner's prototype
/// (`lnp2gus`, run on these same made-up templates; its output is written
/// here as numbers). Curves are compared at their 17 sample points.
@Suite("Preset packs: mapping")
struct PresetPackMappingTests {
    typealias F = PackFixture

    static func points(_ flat: [Double]) -> [CurvePoint] {
        var points: [CurvePoint] = []
        var index = 0
        while index + 1 < flat.count {
            points.append(CurvePoint(x: flat[index], y: flat[index + 1]))
            index += 2
        }
        return points
    }

    static func statuses(_ conversion: LuminarConversion) -> [String] {
        conversion.tools.map { report in
            let name: String
            switch report.tool {
            case .known(let tool): name = "\(tool)"
            case .unknown(let identifier): name = "?\(identifier)"
            }
            return "\(name):\(report.status)"
        }
    }

    // MARK: Develop

    @Test func developInstancesAddUpWithColorSaturation() {
        let result = F.convert([
            F.tool(.develop,
                   F.effect("MIPLDevelopCommonEffectID", F.param("Exposure", -37.5), F.param("Contrast", 12), F.param("Highlights", -25),
                            F.param("Shadows", 18), F.param("Temperature", 14), F.param("Tint", -6)),
                   F.effect("MIPLBlackWhiteEffect", F.param("Whites", 7), F.param("Blacks", -22)),
                   F.effect("MIPLSaturationEffect", F.param("Saturation", -9)), F.effect("MIPLVibranceEffect", F.param("Vibrance", 11))),
            F.tool(.develop, F.effect("MIPLDevelopCommonEffectID", F.param("Contrast", 30), F.param("Exposure", 10))),
            F.tool(.color, F.effect("MIPLSaturationEffect", F.param("Saturation", 4))),
        ])
        let a = result.adjustments
        #expect(a.exposure.ev == -0.55)
        #expect(a.tone == Tone(contrast: 42, highlights: -25, shadows: 18, whites: 7, blacks: -22))
        #expect(a.presence == Presence(vibrance: 11, saturation: -5))
        #expect(a.whiteBalance == WhiteBalance(relativeTemperature: 14, relativeTint: -6))
        #expect(result.groups == [.whiteBalance, .light, .presence])
        #expect(Self.statuses(result) == ["develop:mapped", "color:mapped"])
    }

    @Test func developClampsWhatAddsUpPastTheEnd() {
        let result = F.convert([F.tool(.develop, F.effect("MIPLDevelopCommonEffectID", F.param("Contrast", 60))),
                                F.tool(.develop, F.effect("MIPLDevelopCommonEffectID", F.param("Contrast", 70)))])
        #expect(result.adjustments.tone.contrast == 100)
    }

    @Test func rawDevelopIsUsedOnlyAlone() {
        let raw = F.tool(.rawDevelop, F.effect("MIPLRawDevelopEffect", F.param("Highlights", -45),
                                               F.param("Temperature", 4300, 5200), F.param("Tint", 9, 12)))
        let alone = F.convert([raw])
        #expect(alone.adjustments.tone.highlights == -45)
        #expect(alone.adjustments.whiteBalance == WhiteBalance(preset: .custom, temperature: 4300, tint: 9))
        #expect(Self.statuses(alone) == ["rawDevelop:mapped"])

        let asShot = F.convert([F.tool(.rawDevelop, F.effect("MIPLRawDevelopEffect", F.param("Temperature", 5426, 5426)))])
        #expect(asShot.groups.isEmpty)

        let both = F.convert([raw, F.tool(.develop, F.effect("MIPLDevelopCommonEffectID", F.param("Highlights", -40)))])
        #expect(both.adjustments.tone.highlights == -40)
        #expect(both.adjustments.whiteBalance == WhiteBalance())
        #expect(Self.statuses(both) == ["rawDevelop:leftOut", "develop:mapped"])
    }

    @Test func developCurvesKeepTheirPoints() {
        let result = F.convert([F.tool(.develop, F.effect(
            "MIPLCurveEffect",
            F.curve("RGB", ["0.5", "0", "0", "0.25", "0.2", "0.75", "0.8", "1", "1"]),
            F.curve("R", ["0.5", "0", "0.05", "1", "1"]),
            F.curve("G", ["0.5", "0", "0", "1", "1"])))])
        let curve = result.adjustments.toneCurve
        #expect(curve.rgb == Self.points([0, 0, 0.25, 0.2, 0.75, 0.8, 1, 1]))
        #expect(curve.red == Self.points([0, 0.05, 1, 1]))
        #expect(curve.green == ToneCurve.identityPoints)
        #expect(result.groups == [.toneCurve])
        // The text form packs store, and a value alone, which is no curve.
        let text = F.convert([F.tool(.develop, F.effect("MIPLCurveEffect", F.param("RGB", 0, 50,
                                                                                   option: "['0.5', '0', '0.1', '1', '0.9']")))])
        #expect(text.adjustments.toneCurve.rgb == Self.points([0, 0.1, 1, 0.9]))
        #expect(F.convert([F.tool(.develop, F.effect("MIPLCurveEffect", F.param("RGB", 0, 50)))]).groups.isEmpty)
    }

    @Test func curvesComposeInToolOrderAt17Points() {
        let result = F.convert([
            F.tool(.develop, F.effect("MIPLCurveEffect", F.curve("RGB", ["0.5", "0", "0", "0.5", "0.42", "1", "1"]))),
            F.tool(.supercontrast, F.effect("MIPLSmartContrastEffect", F.param("Shadows", 30), F.param("Midtones", 12),
                                            F.param("MiddleS", 20), F.param("MiddleM", -35))),
            F.tool(.matte, F.effect("MIPLFadeEffect", F.param("Amount", 40), F.param("Fade", 12), F.param("Contrast", 25, 20),
                                    F.param("Saturation", -20, -20))),
        ])
        #expect(result.adjustments.toneCurve.rgb.count == LuminarCurves.sampleCount)
        #expect(result.adjustments.toneCurve.rgb == Self.points([
            0.0, 0.048, 0.0625, 0.0905, 0.125, 0.1348, 0.1875, 0.1848, 0.25, 0.2381, 0.3125, 0.2905, 0.375, 0.3385,
            0.4375, 0.3844, 0.5, 0.4386, 0.5625, 0.5052, 0.625, 0.5779, 0.6875, 0.6512, 0.75, 0.7226, 0.8125, 0.7947,
            0.875, 0.8662, 0.9375, 0.9351, 1.0, 1.0,
        ]))
        #expect(result.adjustments.presence.saturation == -8)
        #expect(Self.statuses(result) == ["develop:mapped", "supercontrast:approximated", "matte:approximated"])
        #expect(result.tools[2].controls == [.toneCurve, .saturation])
    }

    @Test func supercontrastAlone() {
        let result = F.convert([F.tool(.supercontrast, F.effect(
            "MIPLSmartContrastEffect", F.param("Shadows", 20), F.param("Midtones", 45), F.param("Highlights", 10),
            F.param("MiddleS", -40), F.param("MiddleM", 15), F.param("MiddleH", 60)))])
        #expect(result.adjustments.toneCurve.rgb == Self.points([
            0.0, 0.0, 0.0625, 0.0579, 0.125, 0.1172, 0.1875, 0.1843, 0.25, 0.2522, 0.3125, 0.3104, 0.375, 0.3642,
            0.4375, 0.4293, 0.5, 0.5045, 0.5625, 0.5783, 0.625, 0.6409, 0.6875, 0.6931, 0.75, 0.7499, 0.8125, 0.8154,
            0.875, 0.88, 0.9375, 0.9402, 1.0, 1.0,
        ]))
    }

    // MARK: Look-up table

    @Test func lookUpTableAtItsIntensity() {
        let result = F.convert([F.lutTool("table.cube", amount: 85.4, pretty: "Red Rock")],
                               resources: ["TABLE.CUBE": F.identityCube])
        let table = result.adjustments.lookTable
        #expect(table.identifier == Digest.sha256Hex(F.identityCube))
        #expect(table.name == "Red Rock" && table.intensity == 85.4)
        #expect(result.lookTable?.data == F.identityCube)
        #expect(result.lookTable?.name == "Red Rock")
        #expect(result.groups == [.lookTable])
        #expect(Self.statuses(result) == ["lookUpTable:mapped"])
    }

    @Test func lookUpTableContrastAndSaturationAreApproximated() {
        let result = F.convert([F.lutTool(contrast: 10, saturation: -5),
                                F.tool(.develop, F.effect("MIPLDevelopCommonEffectID", F.param("Contrast", 5)))],
                               resources: ["TABLE.CUBE": F.identityCube])
        #expect(result.adjustments.tone.contrast == 15)
        #expect(result.adjustments.presence.saturation == -5)
        // Design §13: the table is exact, its contrast and saturation approximated: listed under both.
        #expect(Self.statuses(result) == ["lookUpTable:mapped", "lookUpTable:approximated", "develop:mapped"])
        #expect(result.tools[0].controls.isEmpty)
        #expect(result.tools[1].controls == [.contrast, .saturation])
    }

    @Test func aMissingOrSecondTableIsLeftOut() {
        let missing = F.convert([F.lutTool("NOPE.CUBE")], resources: ["TABLE.CUBE": F.identityCube])
        #expect(missing.groups.isEmpty && Self.statuses(missing) == ["lookUpTable:leftOut"])
        let two = F.convert([F.lutTool(), F.lutTool()], resources: ["TABLE.CUBE": F.identityCube])
        #expect(two.adjustments.lookTable.identifier != nil)
        #expect(Self.statuses(two) == ["lookUpTable:mapped", "lookUpTable:leftOut"])
    }

    // MARK: Color

    @Test func colorMixerBands() {
        let result = F.convert([F.tool(.color, F.effect("MIPLChannelsEffect", F.param("hRed", 10), F.param("sBlue", -30),
                                                        F.param("lMagenta", 35), F.param("hAqua", 0)))])
        let mixer = result.adjustments.colorMixer
        #expect(mixer[.red] == ColorMixer.Shift(hue: 10))
        #expect(mixer[.blue] == ColorMixer.Shift(saturation: -30))
        #expect(mixer[.magenta] == ColorMixer.Shift(luminance: 35))
        #expect(mixer[.aqua].isZero)
        #expect(result.groups == [.colorMixer])
    }

    @Test func warmthBecomesWarmGrading() {
        let result = F.convert([F.tool("ColorEnhancerAdjustmentLayer", F.effect("MIPLBrillianceWarmthEffect", F.param("Warmth", 35)))])
        let grade = result.adjustments.colorGrade
        #expect(grade.shadows == GradeWheel(hue: 30, amount: 14))
        #expect(grade.midtones == GradeWheel(hue: 30, amount: 28))
        #expect(grade.highlights == GradeWheel(hue: 30, amount: 28))
        #expect(Self.statuses(result) == ["warmth:approximated"])
        #expect(result.tools[0].controls == [.colorGrading])
    }

    @Test func colorBalanceBecomesGrading() {
        let result = F.convert([F.tool("ColorEnhancerAdjustmentLayer", F.effect(
            "MIPLColorBalanceEffect", F.param("SBlue", 12), F.param("SRed", -4), F.param("MGreen", 6),
            F.param("HRed", 15), F.param("HGreen", 9)))])
        let grade = result.adjustments.colorGrade
        #expect(grade.shadows == GradeWheel(hue: 225, amount: 12.8))
        #expect(grade.midtones == GradeWheel(hue: 120, amount: 4.8))
        #expect(grade.highlights == GradeWheel(hue: 36, amount: 12))
        #expect(Self.statuses(result) == ["colorBalance:approximated"])
    }

    @Test func splitToningAndWarmthAddUp() {
        let toning = F.convert([F.tool(.colorToning, F.effect(
            "MIPLSplitToningEffect", F.param("ShadowsHue", 205.5), F.param("ShadowsSaturation", 18), F.param("HighlightsHue", 42),
            F.param("HighlightsSaturation", 12.5), F.param("Balance", -15), F.param("Amount", 70, 50)))])
        var expected = ColorGrade()
        expected.shadows = GradeWheel(hue: 205.5, amount: 25.2)
        expected.highlights = GradeWheel(hue: 42, amount: 17.5)
        expected.balance = -15
        #expect(toning.adjustments.colorGrade == expected)
        #expect(Self.statuses(toning) == ["colorToning:mapped"])

        let both = F.convert([
            F.tool("ColorEnhancerAdjustmentLayer", F.effect("MIPLBrillianceWarmthEffect", F.param("Warmth", -20))),
            F.tool(.colorToning, F.effect("MIPLSplitToningEffect", F.param("ShadowsHue", 200), F.param("ShadowsSaturation", 10))),
        ])
        #expect(both.adjustments.colorGrade.shadows == GradeWheel(hue: 204.4444, amount: 18))
        #expect(both.adjustments.colorGrade.midtones == GradeWheel(hue: 210, amount: 16))
        #expect(both.adjustments.colorGrade.highlights == GradeWheel(hue: 210, amount: 16))
        #expect(F.convert([F.tool(.colorToning, F.effect("MIPLSplitToningEffect", F.param("Balance", 40)))]).groups.isEmpty)
    }

    @Test func vividnessAndWarmAndCoolColors() {
        let result = F.convert([F.tool("ColorEnhancerAdjustmentLayer",
                                       F.effect("MIPLBrillianceWarmthEffect", F.param("Vividness", 10)),
                                       F.effect("MIPLSplitWarmthEffect", F.param("Warm Colors", 0), F.param("Cool Colors", -18.8)))])
        let a = result.adjustments
        #expect(a.presence.vibrance == 10)
        #expect([ColorMixer.Band.aqua, .blue, .purple].map { a.colorMixer[$0].saturation } == [-18.8, -18.8, -18.8])
        #expect(a.colorMixer[.red].isZero)
        #expect(Self.statuses(result) == ["vividness:approximated", "warmAndCoolColors:approximated"])
    }

    // MARK: Detail and effects

    @Test func sharpeningAddsUpAndDetailsBecomeClarity() {
        let result = F.convert([
            F.tool("DetailsEnhancerAdjustmentLayer",
                   F.effect("MIPLSharpenEffect", F.param("Amount", 25, 0), F.param("Radius", 30, 50), F.param("Masking", 40, 35)),
                   F.effect("MIPLDetailsEffect", F.param("Overall_Small_Detail", 4), F.param("Overall_Medium_Detail", 8),
                            F.param("Overall_Large_Detail", 15))),
            F.tool(.develop, F.effect("MIPLSharpenEffect", F.param("Amount", 18, 0), F.param("Radius", 80, 50), F.param("Masking", 10, 35))),
        ])
        #expect(result.adjustments.sharpen == Sharpen(amount: 43, radius: 0.8, masking: 40))
        #expect(result.adjustments.presence.clarity == 9)
        #expect(Self.statuses(result) == ["sharpening:mapped", "detailsEnhancer:approximated"])
    }

    @Test func clarityFromStructureAndDramatic() {
        let result = F.convert([
            F.tool(.structure, F.effect("MIPLAIStructureEffect", F.param("Amount", 20), F.param("Boost", 10))),
            F.tool(.dramatic, F.effect("MIPLComplexBleachEffect", F.param("Amount", 20), F.param("Contrast", 50, 50),
                                       F.param("Local Contrast", 60, 60), F.param("Saturation", -25, -25))),
        ])
        #expect(result.adjustments.presence.clarity == 20 * 0.75 + 0.2 * 60)
        #expect(result.adjustments.tone.contrast == 10)
        #expect(result.adjustments.presence.saturation == -5)
        #expect(Self.statuses(result) == ["structure:approximated", "dramatic:approximated"])
        #expect(result.tools[0].controls == [.clarity])
    }

    @Test(arguments: [(0.0, 0.5), (5.9, 0.6475), (20, 1.0), (47, 1.675), (60, 2.0), (100, 3.0)])
    func grain(size: Double, expected: Double) {
        let result = F.convert([F.tool(.grain, F.effect("MIPLGrainNewEffect", F.param("Amount", 22), F.param("Size", size, 20),
                                                        F.param("Roughness", 61, 30)))])
        #expect(result.adjustments.grain == Grain(strength: 22, roughness: 61, size: expected))
        #expect(result.groups == [.grain])
    }

    @Test func vignetteAndItsStyle() {
        let styled = F.convert([F.tool(.vignette, F.effect("MIPLVignetteEffect", F.param("Amount", -23.5), F.param("Vignette Size", 62, 50),
                                                           F.param("Roundness", 15), F.param("Feather", 30, 50)))])
        #expect(styled.adjustments.vignette == Vignette(amount: -23.5, size: 62, roundness: 15))
        #expect(Self.statuses(styled) == ["vignette:approximated"])
        #expect(styled.tools[0].controls.isEmpty)
        let plain = F.convert([F.tool(.vignette, F.effect("MIPLVignetteEffect", F.param("Amount", 10)))])
        #expect(Self.statuses(plain) == ["vignette:mapped"])
    }

    @Test func dehazeAndTheLandscapeToolsLeftOut() {
        let result = F.convert([F.tool("LandscapeEnhancerAdjustmentLayer",
                                       F.effect(LuminarTool.dehaze.rawValue, F.param("Amount", 20)),
                                       F.effect(LuminarTool.goldenHour.rawValue, F.param("Amount", 15)),
                                       F.effect(LuminarTool.foliage.rawValue, F.param("Amount", 5)))])
        #expect(result.adjustments.presence.dehaze == 20)
        #expect(Self.statuses(result) == ["dehaze:mapped", "goldenHour:leftOut", "foliage:leftOut"])
    }

    // MARK: Black and white

    @Test func blackAndWhiteDropsEarlierTintingAndKeepsLaterToning() {
        let result = F.convert([
            F.tool("ColorEnhancerAdjustmentLayer", F.effect("MIPLBrillianceWarmthEffect", F.param("Warmth", 25))),
            F.tool(.blackAndWhite, F.effect("MIPLBWChannels_v1_Effect", F.param("Apply", 10), F.param("lRed", -24),
                                            F.param("lYellow", 16), F.param("lGreen", 6), F.param("lCyan", 9),
                                            F.param("lBlue", -12), F.param("lViolet", 30))),
            F.tool(.colorToning, F.effect("MIPLSplitToningEffect", F.param("HighlightsHue", 38), F.param("HighlightsSaturation", 14))),
        ])
        let a = result.adjustments
        #expect(a.presence == Presence(saturation: -100))
        let luminance = ColorMixer.Band.allCases.map { a.colorMixer[$0].luminance }
        #expect(luminance == [-24, -4, 16, 6, 9, -12, 30, 3])
        var grade = ColorGrade()
        grade.highlights = GradeWheel(hue: 38, amount: 14)
        #expect(a.colorGrade == grade)
        #expect(Self.statuses(result) == ["blackAndWhite:approximated", "colorToning:mapped"])
        #expect(F.convert([F.tool(.blackAndWhite, F.effect("MIPLBWChannels_v1_Effect", F.param("lRed", -30)))]).groups.isEmpty)
    }

    // MARK: Left out, masked, unknown, disabled (AC6)

    @Test func accentAIAndAMaskAreLeftOutAndSetNothing() {
        let result = F.convert([
            F.tool(.develop, F.effect("MIPLDevelopCommonEffectID", F.param("Contrast", 30))),
            F.tool("AIEnhanceAdjustmentLayer", F.effect(LuminarTool.accentAI.rawValue, F.param("Boost", 40)),
                   F.effect(LuminarTool.skyEnhancer.rawValue, F.param("Amount", 0))),
            F.tool(.color, F.effect("MIPLVibranceEffect", F.param("Vibrance", 20)), mask: "mask-data"),
            F.tool(.structure, F.effect("MIPLAIStructureEffect", F.param("Amount", 12))),
        ])
        #expect(result.adjustments.presence.vibrance == 0)
        #expect(result.adjustments.tone.contrast == 30)
        #expect(result.adjustments.presence.clarity == 9)
        #expect(result.groups == [.light, .presence])
        #expect(Self.statuses(result) == ["develop:mapped", "accentAI:leftOut", "masks:leftOut", "structure:approximated"])
        // Without the left-out tools the values are the same: nothing was set from them.
        let without = F.convert([F.tool(.develop, F.effect("MIPLDevelopCommonEffectID", F.param("Contrast", 30))),
                                 F.tool(.structure, F.effect("MIPLAIStructureEffect", F.param("Amount", 12)))])
        #expect(without.adjustments == result.adjustments)
    }

    @Test func leftOutToolsAreReportedOnlyWhenTheyChangeSomething() {
        let result = F.convert([
            F.tool("AIEnhanceAdjustmentLayer", F.effect(LuminarTool.accentAI.rawValue, F.param("Boost", 0)),
                   F.effect(LuminarTool.skyEnhancer.rawValue, F.param("Amount", 30))),
            F.tool(.glow, F.effect("MIPLOrtonGlowEffect", F.param("Amount", 15))),
            F.tool(.highKey, F.effect("MIPLHighKeyEffect", F.param("Amount", 0))),
            F.tool(.atmosphere, F.effect("MIPLAIFogEffect", F.param("Amount", 17))),
            F.tool(.aiNoiseReduction, F.effect("MIPLDenoiseAIRawEffect", F.param("Level", 0))),
            F.tool(.color, F.effect(LuminarTool.hueShift.rawValue, F.param("Hue", -1.5)),
                   F.effect(LuminarTool.removeColorCast.rawValue, F.param("Amount", 10))),
            F.tool("ColorEnhancerAdjustmentLayer", F.effect(LuminarTool.colorContrast.rawValue, F.param("Amount", 4))),
            F.tool(.develop, F.effect("MIPLDevelopCommonEffectID", F.param("Smart Tone", 20), F.param("Texture", 5),
                                      F.param("Denoise_Luminosity", 3)),
                   F.effect(LuminarTool.lensCorrection.rawValue, F.param("Distortion", 5)),
                   F.effect(LuminarTool.noiseReduction.rawValue, F.param("Amount", 5))),
        ])
        #expect(result.groups.isEmpty)
        #expect(Self.statuses(result) == ["skyEnhancer:leftOut", "glow:leftOut", "atmosphere:leftOut", "hueShift:leftOut",
                                          "removeColorCast:leftOut", "colorContrast:leftOut", "smartTone:leftOut",
                                          "texture:leftOut", "noiseReduction:leftOut", "lensCorrection:leftOut"])
    }

    /// AC10: a tool the table does not know is reported by its identifier, exactly.
    @Test func unknownToolsKeepTheirIdentifiers() {
        let result = F.convert([
            F.tool("BrandNewTool_v2", F.effect("MIPLNew", F.param("Amount", 5))),
            F.tool("BrandNewIdleTool", F.effect("MIPLNew", F.param("Amount", 0))),
            F.tool(.develop, F.effect("MIPLDevelopCommonEffectID", F.param("Contrast", 50)), enabled: false),
            F.tool(.color, F.effect("MIPLUnknownEffect", F.param("Amount", 5))),
            F.tool("", F.effect("X", F.param("Amount", 1))),
            F.tool(.develop, F.effect("MIPLDevelopCommonEffectID", F.param("Brightness", 4))),
        ])
        #expect(result.groups.isEmpty)
        #expect(Self.statuses(result) == ["?BrandNewTool_v2:leftOut", "?MIPLUnknownEffect:leftOut", "?:leftOut", "?Brightness:leftOut"])
    }

    @Test func layerSettingsAreApproximated() {
        let result = F.convert([], layers: [F.layer([F.tool(.color, F.effect("MIPLVibranceEffect", F.param("Vibrance", 20)),
                                                            blendMode: "2")], opacity: "0.5")])
        #expect(result.adjustments.presence.vibrance == 20)
        #expect(Self.statuses(result) == ["layers:approximated", "color:mapped"])
    }

    /// A3: a preset with nothing carried over still converts, with no groups.
    @Test func nothingCarriedOverGivesNoGroups() {
        let result = F.convert([F.tool("AIEnhanceAdjustmentLayer", F.effect(LuminarTool.skyEnhancer.rawValue, F.param("Amount", 30)))])
        #expect(result.groups.isEmpty && result.adjustments == Adjustments())
        #expect(result.tools.allSatisfy { $0.status == .leftOut })
    }

    // MARK: Scales (AC9)

    /// Each assumed scale is a named constant; changing one fails here until this test changes too.
    @Test func assumedScalesAreTheRecordedOnes() {
        #expect(LuminarMapping.exposureRangeEV == 2.0)
        #expect(LuminarMapping.colorBalanceFullScale == 0.2)
        #expect(LuminarMapping.warmthFullScale == 0.1)
        #expect(LuminarMapping.warmthRangeWeights == [.shadows: 0.5, .midtones: 1, .highlights: 1])
        #expect(LuminarMapping.structureToClarity == 0.75)
        #expect(LuminarMapping.detailsToClarity == 1.0)
        #expect(LuminarMapping.splitWarmthToSaturation == 1.0)
        #expect(LuminarMapping.supercontrastGain == 0.5)
        #expect(LuminarMapping.supercontrastPivotTravel == 0.8)
        #expect(LuminarCurves.sampleCount == 17)
        // And each is what the mapping uses.
        let exposure = F.convert([F.tool(.develop, F.effect("MIPLDevelopCommonEffectID", F.param("Exposure", 100)))])
        #expect(exposure.adjustments.exposure.ev == LuminarMapping.exposureRangeEV)
        let structure = F.convert([F.tool(.structure, F.effect("MIPLAIStructureEffect", F.param("Amount", 40)))])
        #expect(structure.adjustments.presence.clarity == 40 * LuminarMapping.structureToClarity)
    }
}
