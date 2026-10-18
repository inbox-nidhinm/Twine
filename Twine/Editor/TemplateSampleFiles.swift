import Foundation
import MotionModel

/// Where the samples empty template slots show (`TemplateSamples`) are:
/// in the app's own resources, whatever project is open.
nonisolated enum TemplateSampleFiles {
    static func url(for id: UUID) -> URL? {
        guard let sample = TemplateSamples.sample(id: id) else { return nil }
        let name = (sample.fileName as NSString).deletingPathExtension
        return Bundle.main.url(forResource: name, withExtension: "jpg")
            ?? Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "TemplateSamples")
    }

    static let ids = Set(TemplateSamples.all.map(\.id))
}
