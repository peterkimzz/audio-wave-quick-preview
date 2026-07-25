import AppKit
import AudioWaveQuickPreviewCore
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    private static let minimapWaveformBucketCount = 700
    private static let mainWaveformBucketCount = 720
    private static let keyboardSeekInterval = 10.0
    /// Zoom-in limit: the waveform never shows less than this much time.
    private static let minimumVisibleDuration = 5.0

    @Published var fileName = "No audio selected"
    @Published var waveform: [Float] = []
    @Published var minimapWaveform: [Float] = []
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    /// Base gain set by Normalize to reach the loudness target (peak-limited).
    @Published private(set) var normalizeBaseDB: Double = 0
    /// Manual by-ear fine-tune added on top of the base.
    @Published private(set) var offsetDB: Double = 0
    @Published private(set) var isBypassed = false
    @Published var targetLoudnessDBFS = GainCalculations.defaultTargetLoudnessDBFS {
        didSet {
            let clamped = GainCalculations.clampTarget(targetLoudnessDBFS)
            if clamped != targetLoudnessDBFS { targetLoudnessDBFS = clamped }
        }
    }
    @Published private(set) var exportProgress: Double?
    /// Progress of the streaming analysis, or nil when no load is in flight.
    @Published private(set) var loadProgress: Double?
    @Published private(set) var lastSavedPath: String?
    @Published private(set) var viewport: WaveformViewport?
    @Published var errorMessage: String?

    private let playbackCoordinator = PlaybackCoordinator()
    private var document: AudioDocument?
    private var playbackTimer: Timer?
    /// URL of the load in flight, used to drop results from a superseded open.
    private var loadingURL: URL?
    private var loadTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?

    init() {
        playbackCoordinator.onStateChange = { [weak self] in
            self?.syncPlaybackState()
        }
    }

    // MARK: - Playhead

    /// Playhead position within the visible span, or nil when it is offscreen.
    var playheadViewRatio: Double? {
        viewport?.viewRatio(for: currentTime)
    }

    var playheadOffscreenDirection: OffscreenIndicatorDirection? {
        viewport?.offscreenIndicatorDirection(for: currentTime)
    }

    /// Playhead position across the whole file, for the minimap.
    var playheadGlobalRatio: Double? {
        guard let viewport, viewport.totalDuration > 0 else { return nil }
        return min(max(currentTime / viewport.totalDuration, 0), 1)
    }

    func handleInitialLaunch(arguments: [String] = CommandLine.arguments) {
        // `document` is only set once the async load finishes, so a second
        // onAppear during loading must not restart it.
        guard document == nil, loadingURL == nil else { return }
        guard let path = arguments.dropFirst().first else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        open(url: url)
    }

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose an audio file"
        panel.prompt = "Open"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = SupportedTypes.allowedTypes

        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        loadTask?.cancel()
        exportTask?.cancel()
        // Before anything else, so a file that fails to decode cannot leave the
        // previous one playing with the transport already reset out from under
        // it. The space-bar monitor bypasses the disabled buttons, so a stale
        // player would still be reachable.
        playbackCoordinator.unload()
        stopPlaybackTimer()

        document = nil
        waveform = []
        minimapWaveform = []
        viewport = nil
        currentTime = 0
        isPlaying = false
        normalizeBaseDB = 0
        offsetDB = 0
        isBypassed = false
        exportProgress = nil
        lastSavedPath = nil
        errorMessage = nil
        fileName = url.lastPathComponent
        loadingURL = url
        loadProgress = 0

        // Wire up the player first: it only parses the header, so playback is
        // available while the waveform is still being analyzed.
        do {
            try playbackCoordinator.load(url: url)
            duration = playbackCoordinator.duration
            viewport = WaveformViewport.full(
                duration: duration,
                minimumVisibleDuration: Self.minimumVisibleDuration
            )
            applyPlaybackVolume()
        } catch {
            loadingURL = nil
            loadProgress = nil
            duration = 0
            errorMessage = error.localizedDescription
            return
        }

        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            let model = self
            do {
                let document = try AudioFileLoader.loadAudioDocument(from: url) { progress in
                    Task { @MainActor in model?.updateLoadProgress(progress, for: url) }
                }
                await MainActor.run { model?.adopt(document) }
            } catch is CancellationError {
                // A newer open() already reset the state it would have published.
            } catch {
                await MainActor.run { model?.failLoad(of: url, with: error) }
            }
        }
    }

    private func updateLoadProgress(_ progress: Double, for url: URL) {
        guard loadingURL == url else { return }
        loadProgress = progress
    }

    private func adopt(_ document: AudioDocument) {
        guard loadingURL == document.url else { return }
        loadingURL = nil
        loadProgress = nil
        self.document = document
        fileName = document.fileName
        duration = document.duration
        viewport = WaveformViewport.full(
            duration: document.duration,
            minimumVisibleDuration: Self.minimumVisibleDuration
        )
        refreshWaveform()
    }

    private func failLoad(of url: URL, with error: Error) {
        guard loadingURL == url else { return }
        loadingURL = nil
        loadProgress = nil
        errorMessage = error.localizedDescription
    }

    func togglePlayback() {
        playbackCoordinator.playPause()
    }

    // MARK: - Gain

    var hasDocument: Bool { document != nil }

    /// Effective gain applied everywhere = Normalize base + fine-tune offset,
    /// snapped and clamped to the valid dB range.
    var gainDB: Double { GainCalculations.snap(normalizeBaseDB + offsetDB) }

    /// Display scale for the waveform (reflects the save gain, ignores bypass).
    var waveformGainScale: Float {
        Float(GainCalculations.linearScale(forDB: gainDB))
    }

    var estimatedPeakDBFS: Double {
        GainCalculations.estimatedPeakDBFS(originalPeak: document?.peak ?? 0, gainDB: gainDB)
    }

    /// Estimated perceived loudness (RMS) after the current gain, in dBFS.
    var estimatedLoudnessDBFS: Double {
        guard let document else { return -.infinity }
        return GainCalculations.dBFS(document.rms) + gainDB
    }

    var isClipping: Bool {
        // Attenuation or unity can't introduce clipping, so an already-hot source
        // (peak ≥ ceiling) is still saveable at 0 dB or below — only a positive
        // gain that pushes the peak past the ceiling blocks Save.
        guard let document, gainDB > 0 else { return false }
        return GainCalculations.isClipping(originalPeak: document.peak, gainDB: gainDB)
    }

    /// True when the peak ceiling puts the loudness target out of reach, so
    /// Normalize can't get there. Derived from the file and the target rather
    /// than from `normalizeBaseDB`, which would miss a file whose safe gain is
    /// exactly 0 dB — the most peak-limited case there is.
    var isPeakLimited: Bool {
        guard let document else { return false }
        return GainCalculations.isPeakLimited(
            currentRMS: document.rms,
            originalPeak: document.peak,
            targetDBFS: targetLoudnessDBFS
        )
    }

    var maxSafeGainDB: Double {
        GainCalculations.maxSafeGainDB(originalPeak: document?.peak ?? 0)
    }

    var canSave: Bool { hasDocument && !isClipping && exportProgress == nil }

    /// Manual by-ear fine-tune, layered on top of the Normalize base.
    func setOffset(_ db: Double) {
        offsetDB = GainCalculations.snapOffset(db)
        lastSavedPath = nil
        applyPlaybackVolume()
    }

    /// "0 dB Reset" — back to the original level (clears base and offset).
    func resetGain() {
        normalizeBaseDB = 0
        offsetDB = 0
        lastSavedPath = nil
        applyPlaybackVolume()
    }

    /// Sets the base gain so the file's RMS lands on `targetLoudnessDBFS`, capped
    /// so the peak never clips. The fine-tune offset is left untouched.
    func normalizeToTarget() {
        guard let document else { return }
        normalizeBaseDB = GainCalculations.gainForTargetLoudness(
            currentRMS: document.rms,
            originalPeak: document.peak,
            targetDBFS: targetLoudnessDBFS
        )
        lastSavedPath = nil
        applyPlaybackVolume()
    }

    func toggleBypass() {
        isBypassed.toggle()
        applyPlaybackVolume()
    }

    private func applyPlaybackVolume() {
        // AVAudioPlayer volume can't exceed unity, so a boost would make the
        // gained and bypassed sides both play at 1.0 (Bypass becomes inaudible).
        // Keep the relative difference audible by attenuating whichever side
        // would exceed 1.0 instead.
        let scale = GainCalculations.linearScale(forDB: gainDB)
        playbackCoordinator.setVolume(Float(isBypassed ? min(1 / scale, 1) : min(scale, 1)))
    }

    func saveAs() {
        guard let document, canSave else { return }

        let panel = NSSavePanel()
        panel.title = "Save gain-adjusted WAV"
        panel.nameFieldStringValue = GainCalculations.outputFileName(
            originalName: document.fileName,
            gainDB: gainDB
        )
        panel.allowedContentTypes = [.wav]

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        startExport(source: document.url, destination: destination, gainDB: gainDB)
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    private func startExport(source: URL, destination: URL, gainDB: Double) {
        errorMessage = nil
        exportProgress = 0
        exportTask?.cancel()
        exportTask = Task.detached(priority: .userInitiated) { [weak self] in
            let model = self
            do {
                try AudioExportService.export(
                    source: source,
                    destination: destination,
                    gainDB: gainDB
                ) { progress in
                    Task { @MainActor in model?.exportProgress = progress }
                }
                await MainActor.run {
                    model?.exportProgress = nil
                    model?.lastSavedPath = destination.path
                }
            } catch is CancellationError {
                await MainActor.run {
                    model?.exportProgress = nil
                }
            } catch {
                await MainActor.run {
                    model?.exportProgress = nil
                    model?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func seek(to ratio: Double) {
        let time: Double
        if let viewport {
            time = viewport.time(forViewRatio: ratio)
        } else {
            let clampedRatio = min(max(ratio, 0), 1)
            time = clampedRatio * duration
        }

        playbackCoordinator.seek(to: time)
        currentTime = time
    }

    func seekByKeyboardOffset(_ delta: Double) {
        let time = PlaybackNavigation.shiftedTime(
            currentTime: currentTime,
            duration: duration,
            delta: delta
        )
        playbackCoordinator.seek(to: time)
        currentTime = time
    }

    func seekBackwardByKeyboardInterval() {
        seekByKeyboardOffset(-Self.keyboardSeekInterval)
    }

    func seekForwardByKeyboardInterval() {
        seekByKeyboardOffset(Self.keyboardSeekInterval)
    }

    func zoomWaveform(scale: Double, anchorRatio: Double) {
        guard let viewport else { return }
        self.viewport = viewport.zoomed(scale: scale, anchorRatio: anchorRatio)
        updateVisiblePresentation()
    }

    func panWaveform(byViewRatio deltaRatio: Double) {
        guard let viewport else { return }
        let deltaTime = viewport.visibleDuration * deltaRatio
        self.viewport = viewport.panned(by: deltaTime)
        updateVisiblePresentation()
    }

    func resetZoom() {
        guard let viewport else { return }
        self.viewport = viewport.reset()
        updateVisiblePresentation()
    }

    func centerOnPlayhead() {
        guard let viewport else { return }
        self.viewport = viewport.centeredOnTime(currentTime)
        updateVisiblePresentation()
    }

    func jumpViewport(toGlobalRatio ratio: Double) {
        guard let viewport else { return }
        self.viewport = viewport.centeredOnGlobalRatio(ratio)
        updateVisiblePresentation()
    }

    func refreshWaveform() {
        guard let document else {
            waveform = []
            minimapWaveform = []
            return
        }

        minimapWaveform = document.pyramid.samples(
            for: .full(duration: document.duration, minimumVisibleDuration: Self.minimumVisibleDuration),
            targetBucketCount: Self.minimapWaveformBucketCount
        )
        updateVisiblePresentation()
    }

    /// Mirrors the player onto the published state. Assigning unconditionally
    /// would fire `objectWillChange` 40×/second even while paused, which redraws
    /// the entire view tree for nothing — hence the equality guards.
    private func syncPlaybackState() {
        let time = playbackCoordinator.currentTime
        if currentTime != time { currentTime = time }

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
        // isolated — no need to hop through a Task per tick.
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

    private func updateVisiblePresentation() {
        guard let document else {
            waveform = []
            minimapWaveform = []
            return
        }

        let viewport =
            (self.viewport
            ?? .full(
                duration: document.duration,
                minimumVisibleDuration: Self.minimumVisibleDuration
            )).updatingMinimumVisibleDuration(Self.minimumVisibleDuration)
        self.viewport = viewport

        waveform = document.pyramid.samples(
            for: viewport,
            targetBucketCount: Self.mainWaveformBucketCount
        )
    }
}

private enum SupportedTypes {
    static let allowedTypes = ["wav", "mp3", "m4a", "flac"].compactMap {
        UTType(filenameExtension: $0)
    }
}
