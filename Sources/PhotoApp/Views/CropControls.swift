import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// The Adjust tab's first heading: the crop frame, its proportions, quarter
/// turns and straightening. The crop button lights up while the loupe shows
/// the crop frame; Done saves and folds the heading away.
struct CropSection: View {
    let editor: AdjustmentEditor
    @State private var isExpanded = SectionHeaderState.isExpanded(key: Self.key, default: true)

    static let key = "adjust.section.crop"

    private var session: CropSession? { editor.cropSession }

    private var isModified: Bool {
        session.map { $0.saved != Crop() } ?? !editor.adjustments.crop.isIdentity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: String(localized: "Crop, Rotate, Straighten"), isExpanded: $isExpanded, key: Self.key) {
                AppKitButton(symbol: "arrow.counterclockwise", style: .borderless, tint: .secondaryLabelColor,
                             help: String(localized: "Reset Crop"), isEnabled: isModified) {
                    editor.resetCrop()
                }
            }
            if isExpanded {
                controls
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppKitButton(title: String(localized: "Crop"), symbol: "crop", style: .borderless,
                             tint: session == nil ? .tertiaryLabelColor : .controlAccentColor,
                             help: session == nil
                                 ? String(localized: "Show the crop frame on the photo")
                                 : String(localized: "Finish cropping (Return); Esc cancels")) {
                    if session == nil { editor.beginCrop() } else { editor.endCrop(save: true) }
                }
                Spacer()
                AppKitButton(symbol: "rotate.left", style: .borderless, tint: .secondaryLabelColor,
                             help: String(localized: "Rotate Left")) {
                    editor.rotate(clockwise: false)
                }
                AppKitButton(symbol: "rotate.right", style: .borderless, tint: .secondaryLabelColor,
                             help: String(localized: "Rotate Right")) {
                    editor.rotate(clockwise: true)
                }
            }
            HStack(spacing: 4) {
                ForEach(CropAspect.allCases, id: \.self) { aspect in
                    aspectButton(aspect)
                    if aspect != CropAspect.allCases.last { Spacer(minLength: 0) }
                }
            }
            AdjustSlider(title: String(localized: "Straighten"),
                         value: session?.crop.angle ?? editor.adjustments.crop.angle,
                         range: Crop.angleRange, defaultValue: 0, format: .degrees) { value, phase in
                editor.straighten(value, phase: phase)
            }
            HStack {
                Spacer()
                AppKitButton(title: String(localized: "Done"), style: .push,
                             help: String(localized: "Save the crop and close this heading"),
                             isEnabled: session != nil) {
                    editor.endCrop(save: true)
                    isExpanded = false
                    UserDefaults.standard.set(false, forKey: Self.key)
                }
            }
        }
    }

    private func aspectButton(_ aspect: CropAspect) -> some View {
        let isActive = session?.aspect == aspect
        let help = aspect == .free
            ? String(localized: "Crop to any proportions")
            : String(localized: "Crop to \(aspect.title); pick it again to swap portrait and landscape",
                     comment: "The argument is an aspect ratio such as 3:2")
        return AppKitButton(title: aspect.title, symbol: aspect == .free ? "rectangle.dashed" : nil,
                            image: Self.icon(aspect), imagePosition: .imageAbove, style: .borderless,
                            font: .systemFont(ofSize: NSFont.smallSystemFontSize),
                            tint: isActive ? .controlAccentColor : .secondaryLabelColor, help: help) {
            editor.setCropAspect(aspect)
        }
    }

    /// An outline of the aspect's proportions, in landscape.
    private static func icon(_ aspect: CropAspect) -> NSImage? {
        guard let ratio = aspect.ratio else { return nil }
        let side: CGFloat = 16
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let width = side - 2
            let height = width / ratio
            let frame = NSRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
            let path = NSBezierPath(roundedRect: frame.insetBy(dx: 0.75, dy: 0.75), xRadius: 1.5, yRadius: 1.5)
            path.lineWidth = 1.5
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
