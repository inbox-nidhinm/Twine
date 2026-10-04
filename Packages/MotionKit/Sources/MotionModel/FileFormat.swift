import Foundation

/// The on-disk shape of a project.
///
/// A `.twine` file is a folder that Finder shows as one file:
///
///     Name.twine/
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
    /// 2 replaced keyframes with actions (September 2026). 3 made pictures
    /// fills on rectangles, as Figma has them, rather than layers of their
    /// own (September 2026).
    public static let currentVersion = 3
    /// Files older than this are refused with a plain message rather than
    /// migrated: nothing made before actions carries over meaningfully.
    public static let oldestReadableVersion = 2

    public static let documentFileName = "document.json"
    public static let mediaFolderName = "media"
    public static let thumbnailFileName = "thumbnail.png"
    public static let fileExtension = "twine"
    public static let typeIdentifier = "com.nidhin.twine.project"
    /// Every ending a project can have.
    public static let readableExtensions = [fileExtension]

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

        // Numbers past what Twine can draw are brought back before anything
        // reads them, migrations included, and the rest is held in range
        // after (`FileSafety`), since a file can come from anyone.
        var body = FileSafety.numbersHeld(data)
        if probe.formatVersion < currentVersion {
            body = try migrator.migrate(body, from: probe.formatVersion, to: currentVersion)
        }
        do {
            return try JSONDecoder().decode(Envelope.self, from: body).project.heldInRange()
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
        case .newerVersion: return "This project was saved by a newer version of Twine."
        case .olderVersion: return "This project was made with an earlier version of Twine, before animation moved to actions, and can no longer be opened."
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

    /// Version 2 is the oldest format still read.
    public static let standard = FormatMigrator(steps: [2: PictureMigration.step])

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

/// Format 2 to 3: every picture layer becomes a rectangle filled with its
/// picture, keeping its id, name, box, transform, effects and mask, so its
/// actions and anything masked by it carry on as before. A picture that
/// filled its box keeps filling it; one stretched out of its own shape
/// keeps its stretch, as a crop of the whole box.
enum PictureMigration {
    static let step: FormatMigrator.Step = { document in
        guard var project = document["project"] as? [String: Any] else { return }
        var sizes: [String: (Double, Double)] = [:]
        for asset in project["media"] as? [[String: Any]] ?? [] {
            if let id = asset["id"] as? String, let w = number(asset["pixelWidth"]), let h = number(asset["pixelHeight"]) {
                sizes[id] = (w, h)
            }
        }
        if let layers = project["layers"] as? [[String: Any]] {
            project["layers"] = try layers.map { try convert($0, sizes: sizes) }
        }
        document["project"] = project
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func convert(_ layer: [String: Any], sizes: [String: (Double, Double)]) throws -> [String: Any] {
        guard var content = layer["content"] as? [String: Any], let type = content["type"] as? String else { return layer }
        var layer = layer
        if type == "group", var group = content["group"] as? [String: Any],
           let children = group["children"] as? [[String: Any]] {
            group["children"] = try children.map { try convert($0, sizes: sizes) }
            content["group"] = group
            layer["content"] = content
            return layer
        }
        guard type == "image", let image = content["image"] as? [String: Any],
              let idText = image["mediaID"] as? String, let mediaID = UUID(uuidString: idText) else { return layer }
        var paint = ImagePaint(mediaID: mediaID)
        let box = layer["size"] as? [String: Any]
        if let w = number(box?["width"]), let h = number(box?["height"]), w > 0, h > 0,
           let (pw, ph) = sizes[idText], pw > 0, ph > 0, abs(w / h - pw / ph) > 0.005 * (pw / ph) {
            paint.mode = .crop
        }
        let shape = ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [Fill(paint: .image(paint))])
        let encoded = try JSONEncoder().encode(shape)
        guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return layer }
        layer["content"] = ["type": "shape", "shape": object]
        return layer
    }
}
