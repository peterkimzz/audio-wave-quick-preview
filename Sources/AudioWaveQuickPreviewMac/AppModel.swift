import AppKit
import AudioWaveQuickPreviewCore
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    private static let laneWaveformBucketCount = 360
    private static let minimapWaveformBucketCount = 360
    private static let keyboardSeekInterval = 10.0
    /// Quick targets shown in the toolbar. The selected folder can also keep
    /// an exact half-decibel value from the target slider in the detail header.
    static let targetPresets = [-6.0, -14.0, -23.0]

    // MARK: - Folders

    /// Folders are saved locations plus their reusable loudness profiles. The
    /// selected folder is the app's current location; its audio files are
    /// loaded into lanes automatically.
    @Published private(set) var folders: [AudioFolder] = []
    @Published private(set) var selectedFolderID: UUID?
    @Published private(set) var isProcessingFolder = false

    // MARK: - Lanes

    @Published private(set) var lanes: [Lane] = []
    @Published var targetLoudnessDBFS = GainCalculations.clampTarget(-14) {
        didSet {
            let clamped = GainCalculations.clampTarget(targetLoudnessDBFS)
            if clamped != targetLoudnessDBFS {
                targetLoudnessDBFS = clamped
                return
            }

            if let selectedFolderID {
                if let index = folders.firstIndex(where: { $0.id == selectedFolderID }) {
                    if folders[index].targetLoudnessDBFS != clamped {
                        folders[index].targetLoudnessDBFS = clamped
                        FolderStore.save(folders)
                    }
                }
            }

            // The base gains were computed for the old target, so they no longer
            // describe what the lanes are set to.
            if isNormalizeApplied { clearNormalize() }
        }
    }
    @Published private(set) var isNormalizeApplied = false
    /// The lane the player is loaded with. `AVAudioPlayer` gives one file at a
    /// time, which matches the mockup's single `playing` slot. Being loaded is
    /// not the same as sounding — see `isPlaying`.
    @Published private(set) var playingURL: URL?
    /// Whether that lane is actually sounding right now. Kept separate from
    /// `playingURL`, which stays put across a pause or a play-through so the lane
    /// keeps its playhead and highlight.
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var exportProgress: Double?
    @Published private(set) var lastExportFolder: String?
    @Published var errorMessage: String?

    private let playbackCoordinator = PlaybackCoordinator()
    private var playbackTimer: Timer?
    /// Analyzed files, kept after a lane is removed so re-checking is instant.
    private var documentCache: [URL: AudioDocument] = [:]
    private var loadTasks: [URL: Task<Void, Never>] = [:]
    private var exportTask: Task<Void, Never>?
    private var folderProcessTask: Task<Void, Never>?

    init() {
        let storedFolders = FolderStore.load()
        folders = storedFolders.isEmpty ? FolderStore.defaultFolders : storedFolders
        selectedFolderID = folders.first?.id
        if storedFolders.isEmpty {
            FolderStore.save(folders)
        }
        targetLoudnessDBFS = selectedFolder?.targetLoudnessDBFS ?? targetLoudnessDBFS

        playbackCoordinator.onStateChange = { [weak self] in
            self?.syncPlaybackState()
        }
        if selectedFolder?.folderURL != nil {
            scanSelectedFolder()
        }
    }

    var selectedFolder: AudioFolder? {
        guard let selectedFolderID else { return nil }
        return folders.first { $0.id == selectedFolderID }
    }

    // MARK: - Folder navigation

    func selectFolder(_ id: UUID) {
        guard folders.contains(where: { $0.id == id }), selectedFolderID != id else { return }

        folderProcessTask?.cancel()
        folderProcessTask = nil
        isProcessingFolder = false
        if isNormalizeApplied { clearNormalize() }

        selectedFolderID = id
        if let folder = selectedFolder {
            targetLoudnessDBFS = folder.targetLoudnessDBFS
        }
        clearStagedFiles()

        if selectedFolder?.folderURL != nil {
            scanSelectedFolder()
        }
    }

    func addFolder() {
        let nameField = NSTextField(string: "New Folder")
        nameField.frame = NSRect(x: 0, y: 0, width: 280, height: 24)

        let alert = NSAlert()
        alert.messageText = "Add Audio Folder"
        alert.informativeText = "Give this folder a name, then choose its location."
        alert.accessoryView = nameField
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let folder = AudioFolder(
            name: name,
            targetLoudnessDBFS: GainCalculations.defaultTargetLoudnessDBFS
        )
        folders.append(folder)
        FolderStore.save(folders)
        selectFolder(folder.id)
        chooseFolder(for: folder.id)
    }

    func chooseFolderForSelectedFolder() {
        guard let selectedFolderID else { return }
        chooseFolder(for: selectedFolderID)
    }

    /// Associates a saved folder with a real directory. Keeping this as a
    /// separate operation makes the folder workflow testable without opening
    /// a native folder picker.
    func assignFolder(_ folderURL: URL, to folderID: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].folderURL = folderURL
        FolderStore.save(folders)

        if selectedFolderID != folderID {
            selectFolder(folderID)
        } else {
            scanSelectedFolder()
        }
    }

    func chooseFolder(for folderID: UUID) {
        guard folders.contains(where: { $0.id == folderID }) else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose the \(folders.first { $0.id == folderID }?.name ?? "folder") location"
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        assignFolder(folder, to: folderID)
    }

    func removeFolder(_ id: UUID) {
        guard folders.count > 1, let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedFolderID == id
        folders.remove(at: index)
        FolderStore.save(folders)

        if wasSelected, let replacement = folders.first {
            selectedFolderID = nil
            selectFolder(replacement.id)
        }
    }

    /// Finder's "Open With" now acts as navigation. It opens the containing
    /// configured folder instead of creating a one-off lane outside the folder
    /// workflow.
    func handleExternalOpen(urls: [URL]) {
        guard let url = urls.first, SupportedTypes.isSupported(url) else {
            errorMessage = "Place supported audio files in one of the configured folders."
            return
        }
        guard
            let folder = folders.first(where: { savedFolder in
                guard let folderURL = savedFolder.folderURL else { return false }
                return url.deletingLastPathComponent().standardizedFileURL == folderURL.standardizedFileURL
            })
        else {
            errorMessage = "This file is not inside a configured folder."
            return
        }

        if selectedFolderID == folder.id {
            scanSelectedFolder()
        } else {
            selectFolder(folder.id)
        }
    }

    /// Reads only the files directly inside the selected folder. The output
    /// directory is intentionally a child named `Normalized`, so generated
    /// files are not treated as new inputs on the next scan.
    func scanSelectedFolder() {
        guard let folder = selectedFolder?.folderURL else {
            errorMessage = "Choose a folder location first."
            return
        }

        clearStagedFiles()
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            let audioURLs =
                urls
                .filter { url in
                    guard SupportedTypes.isSupported(url) else { return false }
                    return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            loadFolderFiles(audioURLs)
            errorMessage = audioURLs.isEmpty ? "No supported audio files found in this folder." : nil
        } catch {
            errorMessage = "Could not read \(folder.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Scans the selected folder, analyzes the files, applies the saved target,
    /// and writes copies to `<input folder>/Normalized` when analysis completes.
    /// This is the one-button workflow for processing newly downloaded files.
    func processSelectedFolder() {
        guard canProcessFolder, let folder = selectedFolder?.folderURL else { return }

        scanSelectedFolder()
        guard !lanes.isEmpty else { return }

        folderProcessTask?.cancel()
        isProcessingFolder = true
        errorMessage = nil
        let outputFolder = folder.appendingPathComponent("Normalized", isDirectory: true)
        folderProcessTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isProcessingFolder = false
                self.folderProcessTask = nil
            }

            do {
                try await self.waitForFolderAnalysis()
                guard !self.lanes.isEmpty else { return }
                self.applyNormalizeToLanes()
                try FileManager.default.createDirectory(
                    at: outputFolder,
                    withIntermediateDirectories: true
                )
                self.startExport(to: outputFolder)
                while self.exportProgress != nil {
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch is CancellationError {
                // The user cancelled processing; no partial output is committed.
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func cancelFolderProcessing() {
        folderProcessTask?.cancel()
        folderProcessTask = nil
        isProcessingFolder = false
        if exportProgress != nil { exportTask?.cancel() }
    }

    private func waitForFolderAnalysis() async throws {
        // A large folder can take a while, but a failed load is surfaced
        // immediately instead of making the one-button action wait for the full
        // timeout.
        for _ in 0..<2_400 {
            try Task.checkCancellation()
            if lanes.allSatisfy({ $0.document != nil }) { return }
            if lanes.contains(where: { $0.document == nil && loadTasks[$0.url] == nil }) {
                throw AudioFileLoaderError.unreadableFile
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AudioFileLoaderError.unreadableFile
    }

    private func loadFolderFiles(_ urls: [URL]) {
        // A download can replace an existing file while keeping the same path.
        // Folder scans must not reuse the old analysis in that case.
        for url in urls {
            documentCache[url] = nil
            do {
                let entry = try AudioFileEntry.read(url)
                var lane = Lane(entry: entry)
                lane.loadProgress = 0
                lanes.append(lane)
                startAnalysis(of: url)
            } catch {
                errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    private func clearStagedFiles() {
        for url in lanes.map(\.url) {
            loadTasks[url]?.cancel()
        }
        loadTasks.removeAll()
        lanes.removeAll()
        if playingURL != nil { stopPlayback() }
        isNormalizeApplied = false
        lastExportFolder = nil
        errorMessage = nil
    }

    private func startAnalysis(of url: URL) {
        loadTasks[url]?.cancel()
        loadTasks[url] = Task.detached(priority: .userInitiated) { [weak self] in
            let model = self
            do {
                let document = try AudioFileLoader.loadAudioDocument(from: url) { progress in
                    Task { @MainActor in model?.updateLoadProgress(progress, for: url) }
                }
                await MainActor.run { model?.adopt(document) }
            } catch is CancellationError {
                // The folder changed or the lane was removed; its state is gone.
            } catch {
                await MainActor.run { model?.failLoad(of: url, with: error) }
            }
        }
    }

    private func updateLoadProgress(_ progress: Double, for url: URL) {
        guard let index = lanes.firstIndex(where: { $0.url == url }) else { return }
        lanes[index].loadProgress = progress
    }

    private func adopt(_ document: AudioDocument) {
        documentCache[document.url] = document
        loadTasks[document.url] = nil
        guard let index = lanes.firstIndex(where: { $0.url == document.url }) else { return }
        adopt(document, into: &lanes[index])
        if isNormalizeApplied { applyNormalize(to: &lanes[index]) }
    }

    private func adopt(_ document: AudioDocument, into lane: inout Lane) {
        let minimum = Lane.minimumVisibleDuration(for: document.duration)
        lane.document = document
        lane.loadProgress = nil
        lane.viewport = .full(duration: document.duration, minimumVisibleDuration: minimum)
        lane.minimapWaveform = document.pyramid.samples(
            for: .full(duration: document.duration, minimumVisibleDuration: minimum),
            targetBucketCount: Self.minimapWaveformBucketCount
        )
        refreshWaveform(of: &lane)
    }

    private func failLoad(of url: URL, with error: Error) {
        loadTasks[url] = nil
        guard let index = lanes.firstIndex(where: { $0.url == url }) else { return }
        lanes[index].loadProgress = nil
        errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
    }

    private func refreshWaveform(of lane: inout Lane) {
        guard let document = lane.document, let viewport = lane.viewport else {
            lane.waveform = []
            return
        }
        lane.waveform = document.pyramid.samples(
            for: viewport,
            targetBucketCount: Self.laneWaveformBucketCount
        )
    }

    // MARK: - Normalize

    func toggleNormalize() {
        if isNormalizeApplied {
            clearNormalize()
        } else {
            applyNormalizeToLanes()
        }
    }

    private func applyNormalizeToLanes() {
        for index in lanes.indices { applyNormalize(to: &lanes[index]) }
        isNormalizeApplied = true
        applyPlaybackVolume()
    }

    /// Sets the base gain so the lane's RMS lands on the target, capped so the
    /// peak never clips. The by-ear ± trim is left alone.
    private func applyNormalize(to lane: inout Lane) {
        guard let document = lane.document else { return }
        lane.normalizeBaseDB = GainCalculations.gainForTargetLoudness(
            currentRMS: document.rms,
            originalPeak: document.peak,
            targetDBFS: targetLoudnessDBFS
        )
    }

    private func clearNormalize() {
        for index in lanes.indices { lanes[index].normalizeBaseDB = 0 }
        isNormalizeApplied = false
        applyPlaybackVolume()
    }

    /// One stepper press: ±1 dB, snapped and clamped by `GainCalculations`.
    func nudge(_ url: URL, by delta: Double) {
        guard let index = lanes.firstIndex(where: { $0.url == url }) else { return }
        lanes[index] = lanes[index].nudged(by: delta)
        lastExportFolder = nil
        applyPlaybackVolume()
    }

    func resetGain(_ url: URL) {
        guard let index = lanes.firstIndex(where: { $0.url == url }) else { return }
        lanes[index].normalizeBaseDB = 0
        lanes[index].offsetDB = 0
        applyPlaybackVolume()
    }

    var clippingLaneCount: Int {
        lanes.filter(\.isClipping).count
    }

    var statusSummary: String {
        let state = isNormalizeApplied ? "normalized" : "original levels"
        return "\(lanes.count) files · \(state)"
    }

    var targetSummary: String {
        String(format: "target %.1f dBFS · RMS", targetLoudnessDBFS)
    }

    var outputHint: String {
        if let folder = selectedFolder?.folderURL {
            return "Originals are kept; copies go to \(folder.appendingPathComponent("Normalized").path)"
        }
        return "Choose a folder to load its audio files"
    }

    var processFolderLabel: String {
        isProcessingFolder ? "Processing…" : "Normalize & Export"
    }

    var canProcessFolder: Bool {
        selectedFolder?.folderURL != nil && !isProcessingFolder && exportProgress == nil
    }

    // MARK: - Audition

    func audition(_ url: URL) {
        if playingURL == url {
            // A file played to the end leaves the player parked at its duration,
            // where play() would finish again instantly. Rewind before resuming.
            if !playbackCoordinator.isPlaying, didReachEnd {
                playbackCoordinator.seek(to: 0)
            }
            playbackCoordinator.playPause()
            return
        }

        startPlayback(of: url)
    }

    private var didReachEnd: Bool {
        playbackCoordinator.duration > 0
            && playbackCoordinator.currentTime >= playbackCoordinator.duration - 0.05
    }

    private func startPlayback(of url: URL) {
        playbackCoordinator.unload()
        do {
            try playbackCoordinator.load(url: url)
            playingURL = url
            currentTime = 0
            applyPlaybackVolume()
            playbackCoordinator.playPause()
        } catch {
            playingURL = nil
            errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func stopPlayback() {
        playbackCoordinator.unload()
        playingURL = nil
        isPlaying = false
        currentTime = 0
        stopPlaybackTimer()
    }

    /// The lane the keyboard acts on: whatever is playing, else the top lane.
    var activeLaneURL: URL? {
        playingURL ?? lanes.first?.url
    }

    func toggleActiveLanePlayback() {
        guard let url = activeLaneURL else { return }
        audition(url)
    }

    func playheadRatio(for lane: Lane) -> Double? {
        guard playingURL == lane.url, let viewport = lane.viewport else { return nil }
        return viewport.viewRatio(for: currentTime)
    }

    func playheadOffscreenDirection(for lane: Lane) -> OffscreenIndicatorDirection? {
        guard playingURL == lane.url else { return nil }
        return lane.viewport?.offscreenIndicatorDirection(for: currentTime)
    }

    func playheadGlobalRatio(for lane: Lane) -> Double? {
        guard playingURL == lane.url, lane.duration > 0 else { return nil }
        return min(max(currentTime / lane.duration, 0), 1)
    }

    private func applyPlaybackVolume() {
        guard let playingURL, let lane = lanes.first(where: { $0.url == playingURL }) else { return }
        // AVAudioPlayer cannot exceed unity, so a boost is expressed by attenuating
        // nothing rather than amplifying — the relative differences between lanes
        // still come through.
        let scale = GainCalculations.linearScale(forDB: lane.gainDB)
        playbackCoordinator.setVolume(Float(min(scale, 1)))
    }

    // MARK: - Playback plumbing

    /// Mirrors the player onto published state. Unconditional assignment would
    /// fire `objectWillChange` 20×/second while paused, redrawing every lane.
    private func syncPlaybackState() {
        let time = playbackCoordinator.currentTime
        if currentTime != time { currentTime = time }

        // The one place `isPlaying` is written. Both a pause and a file running to
        // its end arrive here — via `playPause()` and the player's finish delegate
        // respectively — so neither can leave the lane stuck showing a pause icon.
        let playing = playbackCoordinator.isPlaying
        if isPlaying != playing { isPlaying = playing }

        if playing {
            startPlaybackTimer()
        } else {
            stopPlaybackTimer()
        }
    }

    private func startPlaybackTimer() {
        guard playbackTimer == nil else { return }
        // Scheduled on the main run loop, so the tick is already main-actor
        // isolated — no Task hop per tick.
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncPlaybackState()
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - Viewport

    func seek(_ url: URL, toViewRatio ratio: Double) {
        guard let lane = lanes.first(where: { $0.url == url }) else { return }
        let time = lane.viewport?.time(forViewRatio: ratio) ?? (min(max(ratio, 0), 1) * lane.duration)
        // Seeking a lane that is not the audible one would move the wrong player.
        if playingURL != url { startPlayback(of: url) }
        playbackCoordinator.seek(to: time)
        currentTime = time
    }

    func seekActiveLane(by delta: Double) {
        guard let url = activeLaneURL, let lane = lanes.first(where: { $0.url == url }) else { return }
        if playingURL != url { startPlayback(of: url) }
        let time = PlaybackNavigation.shiftedTime(
            currentTime: currentTime,
            duration: lane.duration,
            delta: delta
        )
        playbackCoordinator.seek(to: time)
        currentTime = time
    }

    func seekActiveLaneBackward() { seekActiveLane(by: -Self.keyboardSeekInterval) }
    func seekActiveLaneForward() { seekActiveLane(by: Self.keyboardSeekInterval) }

    func zoom(_ url: URL, scale: Double, anchorRatio: Double) {
        updateViewport(of: url) { $0.zoomed(scale: scale, anchorRatio: anchorRatio) }
    }

    func pan(_ url: URL, byViewRatio deltaRatio: Double) {
        updateViewport(of: url) { $0.panned(by: $0.visibleDuration * deltaRatio) }
    }

    func resetZoom(_ url: URL) {
        updateViewport(of: url) { $0.reset() }
    }

    func jumpViewport(_ url: URL, toGlobalRatio ratio: Double) {
        updateViewport(of: url) { $0.centeredOnGlobalRatio(ratio) }
    }

    private func updateViewport(of url: URL, _ transform: (WaveformViewport) -> WaveformViewport) {
        guard let index = lanes.firstIndex(where: { $0.url == url }),
            let viewport = lanes[index].viewport
        else {
            return
        }
        // A pan at full view clamps back to the same viewport, as does a pinch at
        // the zoom limit. Assigning anyway would republish `lanes` and redraw every
        // lane for nothing — the expensive half of the old scroll stutter.
        let updated = transform(viewport)
        guard updated != viewport else { return }
        lanes[index].viewport = updated
        refreshWaveform(of: &lanes[index])
    }

    func cancelExport() {
        exportTask?.cancel()
        if isProcessingFolder {
            folderProcessTask?.cancel()
            folderProcessTask = nil
            isProcessingFolder = false
        }
    }

    /// The destination is supplied by the selected folder's `Normalized`
    /// subdirectory, so processing never prompts for a second location.
    func startExport(to folder: URL) {
        // Snapshot the jobs: the lanes can be changed or nudged mid-export, and
        // the running export must keep writing what the user actually confirmed.
        let jobs = lanes.map { lane in
            (
                source: lane.url,
                destination: folder.appendingPathComponent(
                    GainCalculations.outputFileName(originalName: lane.name, gainDB: lane.gainDB)
                ),
                gainDB: lane.gainDB
            )
        }

        errorMessage = nil
        lastExportFolder = nil
        exportProgress = 0
        exportTask?.cancel()
        exportTask = Task.detached(priority: .userInitiated) { [weak self] in
            let model = self
            let total = Double(jobs.count)
            do {
                for (index, job) in jobs.enumerated() {
                    try Task.checkCancellation()
                    try AudioExportService.export(
                        source: job.source,
                        destination: job.destination,
                        gainDB: job.gainDB
                    ) { fileProgress in
                        let overall = (Double(index) + fileProgress) / total
                        Task { @MainActor in model?.exportProgress = overall }
                    }
                }
                await MainActor.run {
                    model?.exportProgress = nil
                    model?.lastExportFolder = folder.path
                }
            } catch is CancellationError {
                await MainActor.run { model?.exportProgress = nil }
            } catch {
                await MainActor.run {
                    model?.exportProgress = nil
                    model?.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

enum SupportedTypes {
    static let extensions = ["wav", "mp3", "m4a", "flac"]

    static let allowedTypes = extensions.compactMap {
        UTType(filenameExtension: $0)
    }

    static func isSupported(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}
