import PhotoCore

/// A photo's name as the library shows it (virtual-copies design §5): the
/// file name for an original, and for a copy made with File ▸ Duplicate the
/// original's name with "copy", "copy 2"… after it. Everything that shows or
/// speaks a photo's name goes through here.
enum PhotoName {
    /// The words of a copy's name, localized as the Finder localizes its
    /// "copy". Export names files with it too (`ExportJob.copyNaming`).
    static let naming = CopyNaming { baseName, number in
        number <= 1
            ? String(localized: "\(baseName) copy",
                     comment: "A copy's name (File ▸ Duplicate): the original's file name without its extension, then “copy”. Also its exported file's name")
            : String(localized: "\(baseName) copy \(number)",
                     comment: "The name of a photo's second and later copies: the original's file name without its extension, “copy”, and a number from 2. Also its exported file's name")
    }

    /// The name without an extension, as the grid's name row shows it:
    /// "IMG_0412", "IMG_0412 copy 2".
    static func display(_ item: CatalogItem) -> String {
        naming.displayName(of: item)
    }

    /// The name where a file is otherwise named in full (the loupe's window
    /// title, the removal confirmation, Activity rows): "IMG_0412.RW2" for an
    /// original; for a copy its name without the extension, since no file of
    /// that name exists on disk.
    static func inFull(_ item: CatalogItem) -> String {
        item.isCopy ? display(item) : item.fileName
    }
}
