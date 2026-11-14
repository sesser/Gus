import Foundation

/// What the Adjust tab says about a raw file the system's RAW decoder gives
/// no image for, which LibRaw decodes instead (issue #161). Such a photo is
/// adjusted as a file that is not RAW; the note says what that leaves out.
enum FallbackDecoderText {
    static let note = String(
        localized: "macOS can't decode this raw file, so it's shown without a profile. Temperature and Tint are relative to the camera's white balance, and Color noise reduction isn't available.",
        comment: "Adjust tab, under the Profile heading, for a raw file the macOS raw decoder cannot read: the app decodes it with its own decoder, which has no Profile or Decoder choice, no Kelvin white balance or named white balance presets, and no Color noise reduction")
}
