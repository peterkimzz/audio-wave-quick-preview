import AVFoundation
import AudioWaveQuickPreviewCore
import Foundation

/// One row in the file inspector. Header-only metadata: opening an `AVAudioFile`
/// parses the format and frame count without decoding a single sample, so a
/// library of a few dozen files resolves instantly. Peak and RMS are deliberately
/// absent — those need a full scan, and they arrive with the `AudioDocument` once
/// the file is checked into a lane.
struct LibraryEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let duration: Double
    let sampleRate: Double

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension }

    var subtitle: String {
        LibraryRowFormatter.subtitle(
            duration: duration,
            fileExtension: fileExtension,
            sampleRate: sampleRate
        )
    }

    /// Restored rows first, then anything added while the restore was still
    /// reading, minus duplicates. Order matters: the persisted library should
    /// keep its shape, with newly opened files appended at the end.
    static func merged(restored: [LibraryEntry], with added: [LibraryEntry]) -> [LibraryEntry] {
        let restoredURLs = Set(restored.map(\.url))
        return restored + added.filter { !restoredURLs.contains($0.url) }
    }

    static func read(_ url: URL) throws -> LibraryEntry {
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.fileFormat.sampleRate
        return LibraryEntry(
            url: url,
            duration: sampleRate > 0 ? Double(file.length) / sampleRate : 0,
            sampleRate: sampleRate
        )
    }
}

/// The library survives quits as plain paths. The app is not sandboxed, so
/// security-scoped bookmarks buy nothing here. Paths are re-read on launch rather
/// than cached with their metadata — the file may have been replaced meanwhile,
/// and a missing one is simply dropped.
enum LibraryStore {
    private static let key = "libraryPaths"

    static func loadPaths(from defaults: UserDefaults = .standard) -> [URL] {
        (defaults.array(forKey: key) as? [String] ?? []).map(URL.init(fileURLWithPath:))
    }

    static func save(_ urls: [URL], to defaults: UserDefaults = .standard) {
        defaults.set(urls.map(\.path), forKey: key)
    }
}
