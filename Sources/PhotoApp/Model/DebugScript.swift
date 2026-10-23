import AppKit
import PhotoCore
import UniformTypeIdentifiers

/// `--debug-script "<commands>"`: drives the UI for development checks without
/// screen recording permission. Commands are separated by ";":
///
///     wait <seconds>        snapshot <file.png>     key <key> [<key>…]
///     loupe | grid          size <points>           focus <index>
///     zoom                  project <n>|all         rating any|unrated|<1-5>
///     flag any|picked|rejected|unflagged|notrejected                 quit
///     pairs grouped|separate  pairfile raw|jpeg     advance on|off
///
/// Keys are characters ("3", "p") or names (left, right, up, down, home, end,
/// pageup, pagedown, return, escape, space); prefix "opt+" or "shift+" for modifiers. Key events go through
/// the window, so they take the same path as real typing.
@MainActor
enum DebugScript {
    private static var started = false

    static func startIfRequested(model: LibraryModel) {
        guard let script = LaunchOptions.current.debugScript, !started else { return }
        started = true
        let commands = script.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        Task {
            // Give the window and the first items time to appear.
            try? await Task.sleep(for: .seconds(1))
            for command in commands where !command.isEmpty {
                await run(command, model: model)
            }
        }
    }

    private static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.className.contains("Window") }
    }

    private static func run(_ command: String, model: LibraryModel) async {
        let parts = command.split(separator: " ").map(String.init)
        guard let verb = parts.first else { return }
        let rest = Array(parts.dropFirst())
        switch verb {
        case "wait":
            try? await Task.sleep(for: .seconds(Double(rest.first ?? "1") ?? 1))
        case "snapshot":
            if let path = rest.first { snapshot(to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath)) }
        case "key":
            for key in rest {
                send(key)
                try? await Task.sleep(for: .milliseconds(80))
            }
        case "loupe":
            model.openLoupe()
        case "grid":
            model.closeLoupe()
        case "size":
            model.thumbnailSize = Double(rest.first ?? "") ?? model.thumbnailSize
        case "focus":
            model.setFocus(Int(rest.first ?? "") ?? 0)
        case "zoom":
            send("z")
        case "project":
            if let index = Int(rest.first ?? ""), model.projects.indices.contains(index) {
                model.sidebarSelection = .project(model.projects[index].id)
            } else {
                model.sidebarSelection = .allPhotos
            }
        case "rating":
            switch rest.first {
            case "unrated": model.ratingRule = .unrated
            case let value?: model.ratingRule = Int(value).map { .atLeast(Rating(clamping: $0)) } ?? .any
            case nil: model.ratingRule = .any
            }
        case "flag":
            let rules: [String: LibraryFilter.FlagRule] = [
                "picked": .picked, "rejected": .rejected, "unflagged": .unflagged, "notrejected": .notRejected,
            ]
            model.flagRule = rules[rest.first ?? ""] ?? .any
        case "pairs":
            model.groupPairs = rest.first != "separate"
        case "pairfile":
            model.showPairFile(raw: rest.first != "jpeg")
        case "advance":
            model.autoAdvance = rest.first == "on"
        case "quit":
            NSApp.terminate(nil)
        default:
            print("debug-script: unknown command \(verb)")
        }
    }

    private static func send(_ spec: String) {
        guard let window else { return }
        var flags: NSEvent.ModifierFlags = []
        var key = spec
        while let range = key.range(of: "+"), key.count > 1 {
            switch key[..<range.lowerBound] {
            case "opt": flags.insert(.option)
            case "shift": flags.insert(.shift)
            case "cmd": flags.insert(.command)
            default: break
            }
            key = String(key[range.upperBound...])
        }
        let named: [String: (UInt16, String)] = [
            "left": (123, "\u{F702}"), "right": (124, "\u{F703}"), "down": (125, "\u{F701}"), "up": (126, "\u{F700}"),
            "return": (36, "\r"), "escape": (53, "\u{1B}"), "space": (49, " "),
            "home": (115, "\u{F729}"), "end": (119, "\u{F72B}"), "pageup": (116, "\u{F72C}"), "pagedown": (121, "\u{F72D}"),
        ]
        let digits: [String: UInt16] = ["0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26]
        let letters: [String: UInt16] = ["p": 35, "x": 7, "u": 32, "z": 6, "[": 33, "]": 30]
        let (code, characters) = named[key] ?? (digits[key] ?? letters[key] ?? 0, key)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil,
                                               characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: code)
            else { continue }
            window.sendEvent(event)
        }
    }

    /// Renders the window's layer tree, which includes layer contents that
    /// `cacheDisplay` would miss.
    private static func snapshot(to url: URL) {
        guard let window, let view = window.contentView?.superview ?? window.contentView, let layer = view.layer else {
            print("debug-script: no window to snapshot")
            return
        }
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.scaleBy(x: scale, y: scale)
        if layer.isGeometryFlipped {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print("debug-script: wrote \(url.path)")
    }
}
