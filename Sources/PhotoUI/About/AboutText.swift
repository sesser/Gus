import Foundation
import PhotoCore

/// The About window's words (issue #179; its design.md, §8).
/// The projects, their pages and their licenses are `Acknowledgements` in
/// PhotoCore; this says what each gave and names its license. Each project's
/// sentence stays on its case's line: `AboutWordingTests` reads them there.
enum AboutText {
    /// App menu and Help menu item, and the About window's title.
    static func aboutTitle(_ appName: String) -> String {
        String(localized: "About \(appName)", comment: "App menu and Help menu item, and the About window's title; the argument is the app's name")
    }

    static func version(_ version: AppVersion) -> String {
        String(localized: "Version \(version.short) (build \(version.build))",
               comment: "About window: the version line, from the bundle; left out when either is missing")
    }

    static func dedication(_ projectName: String) -> String {
        String(localized: "\(projectName) stands on other people's work. Thank you to:",
               comment: "About window: the dedication above the list of projects; the argument is the project's name (the library app's name, also in the standalone importer)")
    }

    /// What a project gave, in one sentence that says what it is to the app:
    /// included code, an approach that was studied, formulas written again,
    /// or a separate program (R3).
    static func summary(of project: Acknowledgement.Project) -> String {
        switch project {
        case .libRaw: String(localized: "Reads raw files macOS can't.", comment: "About window: what LibRaw (a library included in the app) does for it")
        case .darktable: String(localized: "Showed how to apply the lens corrections Fujifilm stores in its raw files. This app's version was written after reading how darktable does it; no code was copied.", comment: "About window: what darktable gave the app. Its approach was studied; none of its code is in the app. Keep that distinction in translation")
        case .lightCraft: String(localized: "The formulas behind brush and color range masks, reimplemented in Swift.", comment: "About window: what LightCraft gave the app. Formulas were reimplemented, not code copied")
        case .grdb: String(localized: "The database toolkit under the catalog.", comment: "About window: what GRDB (a library included in the app) does for it")
        case .exifTool: String(localized: "Reads metadata when it is installed; not part of the app.", comment: "About window: ExifTool is an optional separate program the app uses when present; it is not included")
        }
    }

    /// The project's own license, as a short name.
    static func name(of license: Acknowledgement.License) -> String {
        switch license {
        case .lgpl21: String(localized: "LGPL 2.1", comment: "About window: LibRaw's license, as a short name")
        case .gpl3OrLater: String(localized: "GPL 3 or later", comment: "About window: darktable's license, as a short name")
        case .mit: String(localized: "MIT", comment: "About window: the MIT License, as a short name (LightCraft, GRDB)")
        case .sameAsPerl: String(localized: "Artistic License / GPL, as ExifTool states", comment: "About window: ExifTool's license as ExifTool describes it")
        }
    }

    static var viewLicense: String {
        String(localized: "View License",
               comment: "About window: button that opens a project's or the app's full license text in its own window")
    }

    /// VoiceOver's label for a View License button: whose license it shows.
    static func viewLicenseLabel(_ name: String) -> String {
        String(localized: "View \(name) License",
               comment: "About window: VoiceOver label of the View License button; the argument says whose license")
    }

    /// A license window's title.
    static func licenseTitle(_ name: String) -> String {
        String(localized: "\(name) License", comment: "Title of the window showing a license text, e.g. “LibRaw License”")
    }

    static var copyright: String {
        String(localized: "Copyright © \(AppCopyright.year) \(AppCopyright.holder)",
               comment: "About window: the app's copyright line; the arguments are the year and the copyright holder")
    }

    /// The GPL's short notice, as in the README. Not license text.
    static func freeSoftwareStatement(_ projectName: String) -> String {
        String(localized: "\(projectName) is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3 or (at your option) any later version. It is distributed in the hope that it will be useful, but without any warranty; see the license for details.",
               comment: "About window: the free-software statement (the GPL's short notice, as in the README); the argument is the project's name (the library app's name, also in the standalone importer). Not the license text itself")
    }

    static var licenseMissingTitle: String {
        String(localized: "Can't Show the License", comment: "License window: title when the license file is missing from the app")
    }

    static func licenseMissingDescription(_ appName: String) -> String {
        String(localized: "The license text is missing from this copy of \(appName).",
               comment: "License window: description when the license file is missing; the argument is the app's name")
    }

    /// Whose license a document is: the project's name, or this project's.
    static func owner(of document: LicenseDocument, projectName: String) -> String {
        switch document {
        case .app: projectName
        case .project(let project): Acknowledgements.entry(for: project)?.name ?? project.rawValue
        }
    }
}
