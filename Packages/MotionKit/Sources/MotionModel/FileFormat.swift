import Foundation

/// The on-disk shape of a project.
///
/// A `.emotion` file is a folder that Finder shows as one file:
///
///     Name.emotion/
///         document.json      the project, with its format version
///         media/             every imported file, named by asset id
///         thumbnail.png      for the home screen, written when there is a renderer
///
/// `document.json` is `{ "formatVersion": n, "project": { ... } }`. The version
/// is read on its own first, so a file from an older build can be migrated
/// step by step before it is decoded, and a file from a newer build is refused
/// rather than half-read.
public enum ProjectFormat {
    /// Bump this, and add a migration from the previous version, whenever a
    /// change to the model would make an older file fail to decode or mean
    /// something different.
    ///
    /// 2 replaced keyframes with actions (September 2026).
    public static let currentVersion = 2
    /// Files older than this are refused with a plain message rather than
    /// migrated: nothing made before actions carries over meaningfully.
    public static let oldestReadableVersion = 2

    public static let documentFileName = "document.json"
    public static let mediaFolderName = "media"
    public static let thumbnailFileName = "thumbnail.png"
    public static let fileExtension = "twine"
    public static let typeIdentifier = "com.nidhin.twine.project"
    /// The ending projects had while the app was called eMotion. Such files
    /// still open, and save under the name they have.
    public static let olderFileExtension = "emotion"
    public static let olderTypeIdentifier = "com.nidhin.emotion.project"
    /// Every ending a project can have.
    public static let readableExtensions = [fileExtension, olderFileExtension]

    public static func encode(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        // Sorted and indented, so two versions of a file diff line by line.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope(formatVersion: currentVersion, project: project))
    }

    public static func decode(_ data: Data, migrator: FormatMigrator = .standard) throws -> Project {
        let probe: VersionProbe
        do {
            probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        } catch {
            throw ProjectFileError.unreadable(error.localizedDescription)
        }
        if probe.formatVersion > currentVersion {
            throw ProjectFileError.newerVersion(probe.formatVersion)
        }
        if probe.formatVersion < oldestReadableVersion {
            throw ProjectFileError.olderVersion(probe.formatVersion)
        }

        var body = data
        if probe.formatVersion < currentVersion {
            body = try migrator.migrate(data, from: probe.formatVersion, to: currentVersion)
        }
        do {
            return try JSONDecoder().decode(Envelope.self, from: body).project
        } catch {
            throw ProjectFileError.unreadable(error.localizedDescription)
        }
    }

    private struct Envelope: Codable {
        var formatVersion: Int
        var project: Project
    }

    private struct VersionProbe: Decodable {
        var formatVersion: Int
    }
}

public enum ProjectFileError: Error, Equatable, LocalizedError {
    case unreadable(String)
    case newerVersion(Int)
    case olderVersion(Int)
    case missingMigration(from: Int)
    case missingDocument

    public var errorDescription: String? {
        switch self {
        case .unreadable(let why): return "The project could not be read. \(why)"
        case .newerVersion: return "This project was saved by a newer version of eMotion."
        case .olderVersion: return "This project was made with an earlier version of eMotion, before animation moved to actions, and can no longer be opened."
        case .missingMigration(let v): return "Projects saved in format \(v) cannot be opened by this version."
        case .missingDocument: return "The project is missing its document.json."
        }
    }

    /// The open panel's alert heads itself "could not be opened" and shows
    /// this underneath, so the reason goes here too.
    public var failureReason: String? { errorDescription }
}

/// Upgrades the JSON of an older file one version at a time.
///
/// A migration works on the raw JSON rather than on model types, because the
/// model types only know the current shape. Each step receives the whole
/// document object (with `formatVersion` and `project`) at version `n` and
/// must leave it valid at version `n + 1`; the migrator updates the version
/// number itself.
public struct FormatMigrator: Sendable {
    public typealias Step = @Sendable (inout [String: Any]) throws -> Void

    /// Keyed by the version each step upgrades from.
    public var steps: [Int: Step]

    public init(steps: [Int: Step]) {
        self.steps = steps
    }

    /// No migrations yet: version 2 is the oldest format still read.
    public static let standard = FormatMigrator(steps: [:])

    public func migrate(_ data: Data, from old: Int, to new: Int) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectFileError.unreadable("The document is not a JSON object.")
        }
        for version in old..<new {
            guard let step = steps[version] else { throw ProjectFileError.missingMigration(from: version) }
            try step(&object)
            object["formatVersion"] = version + 1
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
