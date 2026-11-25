import Foundation

/// A gain-map photo's HDR choice (issue #282, R1, R2): the photo is shown and
/// edited in HDR in the loupe, its edited SDR version brightened by the
/// file's gain map as the last step (`GainMap`).
///
/// Stored in the edit stack as its own operation (kind `hdr`, parameter `on`),
/// so undo, History (a revert restores the entry's choice, owner ruling Q3),
/// Reset All Adjustments (which removes it), virtual copies (seeded, then
/// independent) and each file of a RAW+JPEG pair (edits are per file) treat
/// it as every other edit. It is not one of the `Adjustments.Group`s:
/// presets, Copy Adjustments and paste neither carry nor change it (R3).
///
/// It changes no SDR pixel, so it is left out of `EditStack.renderHash`
/// (`EditStack.rendersSDR`): turning it on or off keeps every cached SDR
/// preview, and previews, exports and `photocli render` are byte for byte
/// the same either way (R12). The catalog keeps a copy of it per version
/// (`version.hdr`, migration v17) for the loupe to read without the stack.
///
/// Off is the default and is left out of the stack, so no stack written
/// before this feature holds one (R1).
public struct HDRChoice: AdjustmentModule {
    public static let kind: EditOperationKind = "hdr"

    public var isOn = false

    public init(isOn: Bool = false) {
        self.isOn = isOn
    }

    init(_ values: ParameterValues) {
        isOn = values.bool("on", default: false)
    }

    public var parameters: [String: EditParameter] {
        isOn ? ["on": .bool(true)] : [:]
    }

    public static let parameterDescriptions: [AdjustmentParameter] = [
        AdjustmentParameter("on", .boolean, default: .bool(false)),
    ]
}

extension EditStack {
    /// Whether `operation` can change an SDR render: every enabled operation
    /// but the HDR choice (`HDRChoice`), which only the loupe's HDR version
    /// reads.
    static func rendersSDR(_ operation: EditOperation) -> Bool {
        operation.isEnabled && operation.kind != HDRChoice.kind
    }

    /// The HDR choice the stack holds (`HDRChoice`), as `Adjustments` reads it.
    public var hdrChoice: Bool {
        operations.contains { $0.kind == HDRChoice.kind && $0.kindVersion == 1 && $0.isEnabled
            && $0.parameters["on"] == .bool(true) }
    }
}
