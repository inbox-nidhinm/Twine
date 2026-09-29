import Foundation

/// Brings over what the app kept under its first name, eMotion, the first
/// time it opens as Twine: the projects folder (`eMotion Creations` becomes
/// `Twine Creations`) and the saved settings (the `com.nidhin.emotion`
/// domain, which holds window places, export settings and the timeline's
/// height). Each happens once, only when there is something old and nothing
/// new yet, and never in the test copy, which has its own folder and id.
enum FormerName {
    static let oldFolderName = "eMotion Creations"
    static let oldDefaultsDomain = "com.nidhin.emotion"
    static let bundleID = "com.nidhin.twine"

    static func carryOver() {
        guard Bundle.main.bundleIdentifier == bundleID else { return }
        moveFolder()
        moveSettings()
    }

    private static func moveFolder() {
        guard ProcessInfo.processInfo.environment["TWINE_CREATIONS"] == nil else { return }
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let old = documents.appendingPathComponent(oldFolderName, isDirectory: true)
        let new = Creations.defaultFolder
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        try? fm.moveItem(at: old, to: new)
    }

    private static func moveSettings() {
        let defaults = UserDefaults.standard
        guard let old = defaults.persistentDomain(forName: oldDefaultsDomain), !old.isEmpty,
              defaults.persistentDomain(forName: bundleID)?.isEmpty ?? true else { return }
        defaults.setPersistentDomain(old, forName: bundleID)
        defaults.removePersistentDomain(forName: oldDefaultsDomain)
    }
}
