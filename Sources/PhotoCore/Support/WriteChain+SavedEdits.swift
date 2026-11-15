import Foundation

/// Photos' saved edits, read in order with the window's write chain
/// (reads-beside-write-chain, issue #64).
///
/// A batch change (paste, a preset, Auto Exposure, their undo) reaches the
/// catalog only when its write lands on the chain. A read of the catalog
/// beside the chain can therefore get a photo's stack from before a change
/// already made: Copy Adjustments right after a paste then copies the values
/// from before it, and the next paste gives other photos those. Every read
/// whose result stands for "the photo's edits now" goes through these: they
/// read once every write queued so far has landed, and read again if a
/// write was queued while they read (`read(_:apply:)`).
extension WriteChain {
    /// `versionID`'s saved adjustments, the defaults when the version is
    /// gone. Throws `CancellationError` when the calling task is cancelled,
    /// and the catalog's error when the stack can't be read (a newer build's
    /// or a damaged one; `EditStack.ReadFailure(error)` describes it).
    public func savedAdjustments(ofVersion versionID: Int64, in catalog: Catalog) async throws -> Adjustments {
        let stack = try await read({ try await catalog.version(id: versionID)?.decodedEditStack() ?? .identity },
                                   apply: { _ in })
        return Adjustments(stack: stack)
    }

    /// The saved stacks of `ids`; those this build can't read are listed
    /// apart (`StoredEditStacks.unreadable`). Throws as `savedAdjustments`.
    public func savedEditStacks(forVersions ids: [Int64], in catalog: Catalog) async throws -> StoredEditStacks {
        try await read({ try await catalog.editStacks(forVersions: ids) }, apply: { _ in })
    }
}
