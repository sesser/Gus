import AppKit
import PhotoCore
import PhotoUI
import SwiftUI

/// The pixel magnifier's own words (design §12, §20).
enum PixelMagnifierText {
    static var menuTitle: String { String(localized: "Pixel Magnifier", comment: "View menu and loupe context submenu title") }
    static var rowTitle: String { String(localized: "Pixel magnifier", comment: "Inspector row label") }
    static var popUpLabel: String { String(localized: "Pixel magnifier zoom", comment: "The pop-up's VoiceOver label") }
    static var popUpHelp: String {
        String(localized: "Zoom of the pixel magnifier. Press - or = while picking to change it.",
               comment: "The pop-up's tooltip and VoiceOver help")
    }
    static var zoomIn: String { String(localized: "Pixel Magnifier Zoom In", comment: "Canvas VoiceOver action") }
    static var zoomOut: String { String(localized: "Pixel Magnifier Zoom Out", comment: "Canvas VoiceOver action") }
    static var red: String { String(localized: "R", comment: "The pixel magnifier's plate: red") }
    static var green: String { String(localized: "G", comment: "The pixel magnifier's plate: green") }
    static var blue: String { String(localized: "B", comment: "The pixel magnifier's plate: blue") }
    static var luminance: String { String(localized: "L", comment: "The pixel magnifier's plate: luminance") }

    static func title(_ level: PixelMagnifierLevel) -> String {
        switch level {
        case .percent100: String(localized: "100%", comment: "A zoom level")
        case .percent200: String(localized: "200%", comment: "A zoom level of the pixel magnifier")
        case .percent400: String(localized: "400%", comment: "A zoom level of the pixel magnifier")
        case .percent800: String(localized: "800%", comment: "A zoom level of the pixel magnifier")
        case .percent1600: String(localized: "1600%", comment: "A zoom level of the pixel magnifier")
        }
    }

    static func announcement(_ level: PixelMagnifierLevel) -> String {
        let title = title(level)
        return String(localized: "Pixel magnifier at \(title).", comment: "VoiceOver, after a level change by key, menu or action; %@ is the percentage")
    }
}

extension LibraryModel {
    /// A tool is picking with the magnifier, in the loupe.
    var isPixelMagnifierActive: Bool { mode == .loupe && editor.pixelMagnifierIsPicking }

    /// Sets the level; every path but the inspector's pop-up (which speaks for
    /// itself) announces it.
    func setPixelMagnifierLevel(_ level: PixelMagnifierLevel, announces: Bool = true) {
        guard level != pixelMagnifierLevel else { return }
        pixelMagnifierLevel = level
        if announces { AccessibilityText.announce(PixelMagnifierText.announcement(level)) }
    }

    /// One level up or down, no wrap; false at the end of the list.
    @discardableResult
    func stepPixelMagnifierLevel(up: Bool) -> Bool {
        guard let next = pixelMagnifierLevel.stepped(up: up) else { return false }
        setPixelMagnifierLevel(next)
        return true
    }
}

/// The inspector's Pixel magnifier row: one view a tool places in its own
/// section while it is picking (design §20).
struct PixelMagnifierRow: View {
    let model: LibraryModel

    var body: some View {
        LabeledPopUp(title: PixelMagnifierText.rowTitle) {
            AppKitPopUp(items: PixelMagnifierLevel.allCases.map {
                AppKitPopUp.Item(title: PixelMagnifierText.title($0), tag: String($0.rawValue))
            }, selection: String(model.pixelMagnifierLevel.rawValue), help: PixelMagnifierText.popUpHelp,
               accessibilityLabel: PixelMagnifierText.popUpLabel) { tag in
                model.setPixelMagnifierLevel(PixelMagnifierLevel(stored: Int(tag) ?? 0), announces: false)
            }
        }
    }
}
