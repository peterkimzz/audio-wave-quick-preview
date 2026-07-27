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
    /// Preset targets from the mockup. Sound-effect work snaps to a handful of
    /// house levels rather than sweeping a slider.
    static let targetPresets = [-6.0, -14.0, -23.0]

    // MARK: - Library (the file inspector)

    @Published private(set) var entries: [LibraryEntry] = []
    @Published var searchText = ""
    /// URLs checked into lanes. Kept separate from `lanes` so a check survives
    /// while the file is still being analyzed.
    @Published private(set) var checked: Set<URL> = []

    // MARK: - Lanes

    @Published private(set) var lanes: [Lane] = []
    @Published var targetLoudnessDBFS = GainCalculations.clampTarget(-14) {
        didSet {
            let clamped = GainCalculations.clampTarget(targetLoudnessDBFS)
            if clamped != targetLoudnessDBFS {
                targetLoudnessDBFS = clamped
                return
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

    init() {
        playbackCoordinator.onStateChange = { [weak self] in
            self?.syncPlaybackState()
        }
        restoreLibrary()
    }

    // MARK: - Library

    var filteredEntries: [LibraryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var selectionSummary: String {
        "\(checked.count) of \(entries.count) selected"
    }

    var areAllChecked: Bool {
        !entries.isEmpty && checked.count == entries.count
    }

    private func restoreLibrary() {
        let urls = LibraryStore.loadPaths()
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            // Files can vanish between runs; a missing one is dropped silently
            // rather than greeting the user with an error on every launch.
            let restored = urls.compactMap { try? LibraryEntry.read($0) }
            await MainActor.run { self?.adoptRestored(restored) }
        }
    }

    /// Merges rather than assigns. This read is slow enough (a header parse per
    /// file) that `handleInitialLaunch` and Finder's "Open With" routinely land
    /// first; assigning would drop the file the user actually launched with,
    /// leaving it as a lane with no sidebar row, and shrink the persisted library
    /// to just that file on the next mutation.
    private func adoptRestored(_ restored: [LibraryEntry]) {
        entries = LibraryEntry.merged(restored: restored, with: entries)
        LibraryStore.save(entries.map(\.url))
    }

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "Add audio to the library"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = SupportedTypes.allowedTypes

        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }

    /// Adds files to the library without disturbing what is already staged.
    /// Newly added files are checked, so a drop lands straight in a lane.
    func add(urls: [URL]) {
        let known = Set(entries.map(\.url))
        var added: [LibraryEntry] = []

        for url in urls where !known.contains(url) {
            guard SupportedTypes.isSupported(url) else { continue }
            do {
                added.append(try LibraryEntry.read(url))
            } catch {
                errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        guard !added.isEmpty else { return }
        entries.append(contentsOf: added)
        LibraryStore.save(entries.map(\.url))
        for entry in added { check(entry.url) }
    }

    func remove(url: URL) {
        entries.removeAll { $0.url == url }
        LibraryStore.save(entries.map(\.url))
        uncheck(url)
        documentCache[url] = nil
    }

    func handleInitialLaunch(arguments: [String] = CommandLine.arguments) {
        let urls = arguments.dropFirst()
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        add(urls: urls)
    }

    // MARK: - Checking files into lanes

    func toggle(_ url: URL) {
        if checked.contains(url) {
            uncheck(url)
        } else {
            check(url)
        }
    }

    func toggleSelectAll() {
        if areAllChecked {
            for url in entries.map(\.url) { uncheck(url) }
        } else {
            for url in entries.map(\.url) { check(url) }
        }
    }

    private func check(_ url: URL) {
        guard !checked.contains(url), let entry = entries.first(where: { $0.url == url }) else { return }
        checked.insert(url)

        var lane = Lane(entry: entry)
        if let cached = documentCache[url] {
            adopt(cached, into: &lane)
            lanes.append(lane)
            return
        }

        lane.loadProgress = 0
        lanes.append(lane)
        startAnalysis(of: url)
    }

    private func uncheck(_ url: URL) {
        checked.remove(url)
        lanes.removeAll { $0.url == url }
        loadTasks[url]?.cancel()
        loadTasks[url] = nil
        if playingURL == url { stopPlayback() }
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
                // The lane was unchecked; its state is already gone.
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
            for index in lanes.indices { applyNormalize(to: &lanes[index]) }
            isNormalizeApplied = true
            applyPlaybackVolume()
        }
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
        return "\(lanes.count) lanes · \(state)"
    }

    var targetSummary: String {
        String(format: "target %.1f dBFS · RMS", targetLoudnessDBFS)
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
        lanes[index].viewport = transform(viewport)
        refreshWaveform(of: &lanes[index])
    }

    // MARK: - Batch export

    var canExport: Bool {
        !lanes.isEmpty && lanes.allSatisfy { $0.document != nil } && exportProgress == nil
    }

    var exportLabel: String {
        "Export \(lanes.count) Copies…"
    }

    func exportLanes() {
        guard canExport else { return }
        let clipping = lanes.filter(\.isClipping)
        guard clipping.isEmpty else {
            errorMessage =
                "Too loud to export: \(clipping.map(\.name).joined(separator: ", ")). Lower the gain."
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose a destination folder"
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        startExport(to: folder)
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    /// Split from `exportLanes()` so the destination can be supplied without a
    /// panel — `NSOpenPanel` cannot run in a headless self-check.
    func startExport(to folder: URL) {
        // Snapshot the jobs: the lanes can be re-checked or nudged mid-export, and
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
