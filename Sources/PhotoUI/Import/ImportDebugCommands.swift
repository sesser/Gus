import AppKit
import PhotoCore

/// The `import …` commands of `--debug-script`, shared by the library app and
/// the standalone importer:
///
///     import source <path> | dest <path> | job <text> | delete on|off | eject on|off
///            | run (waits) | confirm yes|no | snapshot <file> | print
@MainActor
public enum ImportDebugCommands {
    /// Runs one command (the words after "import"). Returns false for a command
    /// it does not know, so the caller can try its own.
    @discardableResult
    public static func run(_ words: [String], model: CardImportModel, window: NSWindow?) async -> Bool {
        let argument = words.dropFirst().joined(separator: " ")
        switch words.first {
        case "source":
            model.source = ImportSource.describe(URL(fileURLWithPath: argument))
            try? await Task.sleep(for: .milliseconds(100))
            while model.isScanning { try? await Task.sleep(for: .milliseconds(100)) }
        case "dest":
            model.destination = URL(fileURLWithPath: argument)
        case "job":
            model.jobCode = argument
        case "delete":
            model.deletesOriginals = argument == "on"
        case "eject":
            model.ejectsWhenDone = argument == "on"
        case "run":
            model.startImport()
            try? await Task.sleep(for: .milliseconds(100))
            while model.isImporting { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(500))
        case "confirm":
            model.confirmDeletion(argument == "yes")
            try? await Task.sleep(for: .seconds(1))
        case "snapshot":
            if let window { WindowSnapshot.write(window, to: URL(fileURLWithPath: argument)) }
        case "print":
            printState(model)
        default:
            return false
        }
        return true
    }

    public static func printState(_ model: CardImportModel) {
        let camera = model.camera.map { "\($0.name) count \($0.shutterCount.map(String.init) ?? "-") from \($0.fileName)" }
        print("debug-script: import source \(model.source?.name ?? "-") card \(model.source?.isCard == true) "
              + "shots \(model.shots.count) duplicates \(model.duplicateCount) selected \(model.selectedShots.count) "
              + "deletion \(model.pendingDeletion?.count ?? 0) message \(model.message ?? "-") "
              + "camera \(camera ?? "-")")
    }
}
