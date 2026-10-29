import AppKit
import PhotoCore
import PhotoUI

/// The debug script's export commands (see `DebugScript`):
///
///     export window                 (opens the export window for the selection)
///     export windowshot <png>
///     export set <key>=<value>…     format=jpeg|tiff  bits=8|16  compression=none|lzw|zip
///                                   color=srgb|p3|adobe|prophoto  quality=<0…1>  ppi=<n>
///                                   size=full|long:<n>|short:<n>|fit:<w>x<h>|percent:<n>
///                                   sharpen=off|light|standard|strong[:print]
///                                   meta=all|nolocation|copyright|none  names=original|template
///                                   dest=<folder>  reveal=on|off
///                                   watermark=<png>|off  anchor=<name>  wmsize=<n>  margin=<n>  opacity=<0…1>
///     export template <text>        (the file name template; also switches names to it)
///     export run [keepboth|overwrite|skip]   (waits, then prints the summary)
///     export preset save|apply|delete <name>
///     export print                  (the targets, settings and destination)
@MainActor
enum DebugExportCommands {
    static func run(_ words: [String], model: LibraryModel) async {
        let export = model.export
        let argument = words.dropFirst().joined(separator: " ")
        switch words.first {
        case "window":
            export.begin()
            try? await Task.sleep(for: .milliseconds(800))
        case "windowshot":
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == String(localized: "Export") }) else {
                print("debug-script: the export window is not open")
                return
            }
            WindowSnapshot.write(window, to: URL(fileURLWithPath: (argument as NSString).expandingTildeInPath))
        case "set":
            for pair in words.dropFirst() {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                set(parts[0], parts[1], on: export)
            }
        case "template":
            export.settings.fileNameTemplate = argument
            export.settings.naming = .template
        case "run":
            if export.versionIDs.isEmpty { export.begin() }
            let policy = ExportConflictPolicy.allCases.first { $0.rawValue.lowercased() == words.dropFirst().first }
                ?? .keepBoth
            if await !export.requestExport() {
                if export.conflict != nil {
                    print("debug-script: export conflicts \(export.conflict?.count ?? 0), using \(policy.rawValue)")
                    export.resolveConflict(policy)
                } else {
                    print("debug-script: export did not start: \(export.message ?? "")")
                    return
                }
            }
            while export.isExporting { try? await Task.sleep(for: .milliseconds(100)) }
            if let summary = export.lastSummary {
                print("debug-script: exported \(summary.written.count) to \(summary.destination.path)"
                      + " skipped \(summary.skippedExisting) videos \(summary.skippedVideos)"
                      + " failed \(summary.failures.count) cancelled \(summary.cancelled)")
                for url in summary.written { print("debug-script:   \(url.lastPathComponent)") }
                for failure in summary.failures { print("debug-script:   \(ExportModel.text(failure))") }
            }
        case "preset":
            let name = words.dropFirst(2).joined(separator: " ")
            await export.refreshPresets()
            switch words.dropFirst().first {
            case "save":
                export.savePreset(named: name)
                try? await Task.sleep(for: .milliseconds(300))
            case "apply":
                export.applyPreset(id: export.presets.first { $0.name == name }?.id)
            case "delete":
                export.applyPreset(id: export.presets.first { $0.name == name }?.id)
                export.deleteSelectedPreset()
                try? await Task.sleep(for: .milliseconds(300))
            default:
                break
            }
            print("debug-script: export presets " + export.presets.map(\.name).joined(separator: ", "))
        default:
            print("debug-script: export \(export.versionIDs.count) photos (videos \(export.skippedVideos)) to \(export.destination.path)")
            print("debug-script: export settings \((try? export.settings.jsonString()) ?? "")")
        }
    }

    private static func set(_ key: String, _ value: String, on export: ExportModel) {
        var settings = export.settings
        switch key {
        case "format":
            settings.format = ExportSettings.FileFormat(rawValue: value) ?? settings.format
        case "bits":
            settings.tiffBitDepth = Int(value) == 8 ? 8 : 16
        case "compression":
            settings.tiffCompression = ExportSettings.TIFFCompression(rawValue: value) ?? settings.tiffCompression
        case "color":
            let spaces: [String: ExportSettings.ColorSpace] = ["srgb": .sRGB, "p3": .displayP3, "adobe": .adobeRGB,
                                                               "prophoto": .proPhoto]
            settings.colorSpace = spaces[value.lowercased()] ?? settings.colorSpace
        case "quality":
            settings.jpegQuality = Double(value) ?? settings.jpegQuality
        case "ppi":
            settings.ppi = Int(value) ?? settings.ppi
        case "size":
            let parts = value.split(separator: ":").map(String.init)
            switch parts.first {
            case "long": settings.sizing = .longEdge
            case "short": settings.sizing = .shortEdge
            case "fit": settings.sizing = .fit
            case "percent": settings.sizing = .percent
            default: settings.sizing = .full
            }
            if parts.count > 1 {
                if settings.sizing == .fit {
                    let box = parts[1].split(separator: "x").compactMap { Int($0) }
                    if box.count == 2 { (settings.boxWidth, settings.boxHeight) = (box[0], box[1]) }
                } else if settings.sizing == .percent {
                    settings.percent = Double(parts[1]) ?? settings.percent
                } else {
                    settings.edgeLength = Int(parts[1]) ?? settings.edgeLength
                }
            }
        case "sharpen":
            let parts = value.split(separator: ":").map(String.init)
            settings.sharpening = ExportSettings.SharpeningAmount(rawValue: parts.first ?? "") ?? .off
            settings.sharpeningTarget = parts.dropFirst().first == "print" ? .print : .screen
        case "meta":
            let modes: [String: ExportSettings.Metadata] = ["all": .all, "nolocation": .noLocation,
                                                            "copyright": .copyright, "none": .none]
            settings.metadata = modes[value.lowercased()] ?? settings.metadata
        case "names":
            settings.naming = ExportSettings.Naming(rawValue: value) ?? settings.naming
        case "dest":
            export.destination = URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
        case "reveal":
            export.revealsInFinder = value == "on"
        case "watermark":
            if value == "off" {
                settings.watermarkEnabled = false
            } else {
                export.useWatermark(at: URL(fileURLWithPath: (value as NSString).expandingTildeInPath))
                settings = export.settings
            }
        case "anchor":
            if let anchor = Watermark.Anchor.allCases.first(where: { $0.rawValue.lowercased() == value.lowercased() }) {
                settings.watermark?.anchor = anchor
            }
        case "wmsize":
            if let number = Double(value) { settings.watermark?.size = number }
        case "margin":
            if let number = Double(value) { settings.watermark?.margin = number }
        case "opacity":
            if let number = Double(value) { settings.watermark?.opacity = number }
        default:
            print("debug-script: unknown export setting \(key)")
        }
        export.settings = settings
    }
}
