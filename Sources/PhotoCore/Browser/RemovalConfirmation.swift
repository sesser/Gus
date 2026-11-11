/// What the confirmation before a removal from the library says
/// (docs/features/library-ops, R7–R10; design §6.2 and §7.2); the UI puts it
/// into words. The sentences are in the order they are shown.
public struct RemovalConfirmation: Hashable, Sendable {
    public enum Title: Hashable, Sendable {
        /// One photo, by the file name its cell shows.
        case photo(fileName: String)
        /// Several, counted as the grid shows them (a grouped pair once).
        case photos(Int)
        case project(name: String)
    }

    public enum Sentence: Hashable, Sendable {
        /// "Its ‹N› photos are removed with it."
        case projectPhotos(Int)
        /// "It has no photos."
        case projectHasNoPhotos
        /// "Both files of each RAW+JPEG pair are removed, ‹F› files in all."
        case pairFiles(Int)
        /// "Its ‹K› albums are deleted." (albums and smart albums together)
        case projectAlbums(Int)
        /// Files and sidecars stay, edits are lost, no undo.
        case photosConsequences
        /// The same for a project: the folder stays too.
        case projectConsequences
        /// "The folder stays on disk, unchanged."
        case emptyProjectConsequences
    }

    public var title: Title
    public var sentences: [Sentence]

    /// Removing `shown` photos (the command's targets), which takes
    /// `fileCount` files. `fileName` is the one target's, when there is one.
    /// The pair sentence is there only when pairs add files beyond what the
    /// person selected.
    public static func photos(shown: Int, fileName: String?, fileCount: Int) -> RemovalConfirmation {
        var sentences: [Sentence] = []
        if fileCount > shown { sentences.append(.pairFiles(fileCount)) }
        sentences.append(.photosConsequences)
        let title: Title = if shown == 1, let fileName { .photo(fileName: fileName) } else { .photos(shown) }
        return RemovalConfirmation(title: title, sentences: sentences)
    }

    /// Removing a project with `photoCount` photos as the sidebar counts
    /// them, `fileCount` files and `albumCount` albums and smart albums of
    /// its own.
    public static func project(name: String, photoCount: Int, fileCount: Int, albumCount: Int) -> RemovalConfirmation {
        var sentences: [Sentence] = [photoCount > 0 ? .projectPhotos(photoCount) : .projectHasNoPhotos]
        if fileCount > photoCount { sentences.append(.pairFiles(fileCount)) }
        if albumCount > 0 { sentences.append(.projectAlbums(albumCount)) }
        sentences.append(photoCount > 0 ? .projectConsequences : .emptyProjectConsequences)
        return RemovalConfirmation(title: .project(name: name), sentences: sentences)
    }

    public static func project(_ plan: ProjectRemovalPlan) -> RemovalConfirmation {
        project(name: plan.project.name, photoCount: plan.photoCount, fileCount: plan.fileCount,
                albumCount: plan.albumCount)
    }
}

/// Whether a removal may start (design §6.1, §7.1 and §8): one at a time,
/// and never beside an import. An import writes into a project, and fails
/// if that project is removed under it. An export and a batch measurement
/// are no obstacle: an export works from what it read when it started, and
/// a measurement writes only to the photos still there when it ends.
public enum RemovalAvailability {
    public static func canStart(isRemoving: Bool, isAddingFolders: Bool, isCopying: Bool) -> Bool {
        !(isRemoving || isAddingFolders || isCopying)
    }
}

/// The photo the browser focuses after a removal (design §6.3): the one that
/// followed the last removed photo in the grid's order, or the nearest one
/// before it when none followed.
public enum RemovalFocus {
    /// `isRemoved`: whether the photo at an index is taken by the removal
    /// (the targets, and with pairs ungrouped their partners).
    public static func index(count: Int, isRemoved: (Int) -> Bool) -> Int? {
        guard let last = (0..<count).last(where: isRemoved) else { return nil }
        if last + 1 < count { return last + 1 }
        return (0..<last).last { !isRemoved($0) }
    }
}
