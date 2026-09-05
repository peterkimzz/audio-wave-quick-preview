import Foundation

/// A saved folder and its loudness profile.
///
/// A folder is the app's main unit of work. Its target is a reusable house
/// level for the audio files inside it: for example, a project may want
/// background music quieter than sound effects.
struct AudioFolder: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var folderURL: URL?
    var targetLoudnessDBFS: Double

    init(
        id: UUID = UUID(),
        name: String,
        folderURL: URL? = nil,
        targetLoudnessDBFS: Double
    ) {
        self.id = id
        self.name = name
        self.folderURL = folderURL
        self.targetLoudnessDBFS = targetLoudnessDBFS
    }

    var folderName: String? {
        folderURL?.lastPathComponent
    }
}

enum FolderStore {
    private static let key = "audioFolders"
    /// Settings from the previous category-based version are migrated once.
    private static let legacyKey = "audioCategories"

    /// These are starting points, not universal mixing standards. They give a
    /// new project useful folders immediately while keeping every value
    /// editable and persistent.
    static let defaultFolders = [
        AudioFolder(
            id: UUID(uuidString: "B1C4D2E4-53B8-4CF2-9CA3-2AF65A7FEA01")!,
            name: "BGM",
            targetLoudnessDBFS: -23
        ),
        AudioFolder(
            id: UUID(uuidString: "4D70F267-8B66-4CCF-A4A8-2DF8BB4C8B02")!,
            name: "Sound Effects",
            targetLoudnessDBFS: -14
        ),
        AudioFolder(
            id: UUID(uuidString: "D81ED11E-1F18-4A4B-B1BA-8FD1B87A7C03")!,
            name: "Ambience",
            targetLoudnessDBFS: -18
        ),
    ]

    static func load(from defaults: UserDefaults = .standard) -> [AudioFolder] {
        if let data = defaults.data(forKey: key) {
            if let folders = try? JSONDecoder().decode([AudioFolder].self, from: data) {
                return folders
            }
        }

        // Keep a user's saved targets and folder locations when moving from
        // the old UI terminology. The next save uses the new key.
        guard let data = defaults.data(forKey: legacyKey) else { return [] }
        guard let folders = try? JSONDecoder().decode([AudioFolder].self, from: data) else {
            return []
        }
        save(folders, to: defaults)
        return folders
    }

    static func save(_ folders: [AudioFolder], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        defaults.set(data, forKey: key)
    }
}
