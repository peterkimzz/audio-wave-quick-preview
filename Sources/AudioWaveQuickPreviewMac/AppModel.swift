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
    @Published private(set) var lastSavedPath: String?
    @Published var threshold: Double = 0.025
    @Published var minimumSoundDuration: Double = 0.12
    @Published var mergeSilenceDuration: Double = 0.08
    @Published var minimumVisibleDuration: Double = 5
    @Published private(set) var viewport: WaveformViewport?
    @Published var statusMessage = "Open an audio file to inspect where sound is present."
    @Published var errorMessage: String?

    private let playbackCoordinator = PlaybackCoordinator()
    private var document: AudioDocument?
    private var waveformPyramid: WaveformPyramid?
    private var waveformPyramidSourceURL: URL?
    private var waveformCachePendingURL: URL?
    private var detectedSegments: [SoundSegment] = []
    private var playbackTimer: Timer?
    private var waveformBuildTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?

    init() {
        playbackCoordinator.onStateChange = { [weak self] in
            guard let self else { return }
            self.currentTime = self.playbackCoordinator.currentTime
            self.isPlaying = self.playbackCoordinator.isPlaying
        }
    }

    func handleInitialLaunch(arguments: [String] = CommandLine.arguments) {
        guard document == nil else { return }
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
        do {
            let document = try AudioFileLoader.loadAudioDocument(from: url)
            try playbackCoordinator.load(url: url)
            self.document = document
            waveformPyramid = nil
            waveformPyramidSourceURL = nil
            waveformCachePendingURL = nil
            waveformBuildTask?.cancel()
            fileName = document.fileName
            duration = document.duration
            currentTime = 0
            normalizeBaseDB = 0
            offsetDB = 0
            isBypassed = false
            exportTask?.cancel()
            exportProgress = nil
            lastSavedPath = nil
            applyPlaybackVolume()
            viewport = WaveformViewport.full(
                duration: document.duration,
                minimumVisibleDuration: minimumVisibleDuration
            )
            errorMessage = nil
            refreshAnalysis()
            startPlaybackTimerIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Unable to open the selected file."
        }
    }

    func togglePlayback() {
        playbackCoordinator.playPause()
        isPlaying = playbackCoordinator.isPlaying
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

        // The "Loudness" readout below the slider shows the resulting value, so
        // keep this line number-free to avoid a duplicate dBFS in the title area.
        // Reachability is judged on the base alone (before the by-ear offset).
        let reached = GainCalculations.dBFS(document.rms) + normalizeBaseDB
        if reached < targetLoudnessDBFS - 0.05 {
            statusMessage = "Peak limit reached — couldn't fully reach the target."
        } else {
            statusMessage = "Normalized to target."
        }
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
                    model?.statusMessage = "Saved \(destination.lastPathComponent)"
                }
            } catch is CancellationError {
                await MainActor.run {
                    model?.exportProgress = nil
                    model?.statusMessage = "Export canceled."
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
        isPlaying = playbackCoordinator.isPlaying
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

    func updateMinimumVisibleDuration() {
        guard let viewport else { return }
        self.viewport = viewport.updatingMinimumVisibleDuration(minimumVisibleDuration)
        updateVisiblePresentation()
    }

    func jumpViewport(toGlobalRatio ratio: Double) {
        guard let viewport else { return }
        self.viewport = viewport.centeredOnGlobalRatio(ratio)
        updateVisiblePresentation()
    }

    func refreshAnalysis() {
        guard let document else {
            waveform = []
            minimapWaveform = []
            waveformPyramid = nil
            waveformPyramidSourceURL = nil
            waveformCachePendingURL = nil
            statusMessage = "Open an audio file to inspect where sound is present."
            return
        }

        let result = AudioAnalysisEngine.analyze(
            samples: document.samples,
            sampleRate: document.sampleRate,
            configuration: AnalysisConfiguration(
                threshold: Float(threshold),
                minimumSoundDuration: minimumSoundDuration,
                mergeSilenceDuration: mergeSilenceDuration,
                waveformBucketCount: Self.minimapWaveformBucketCount
            )
        )

        detectedSegments = result.segments
        statusMessage = makeStatusMessage(segments: result.segments, duration: document.duration)

        if waveformPyramidSourceURL == document.url, waveformPyramid != nil {
            updateVisiblePresentation()
            return
        }

        minimapWaveform = result.waveform

        if waveformCachePendingURL != document.url {
            buildWaveformCache(for: document)
        }

        updateVisiblePresentation()
    }

    private func makeStatusMessage(segments: [SoundSegment], duration: Double) -> String {
        let segmentCount = segments.count
        if segmentCount == 0 {
            return "No sound sections detected at the current sensitivity."
        }

        let soundDuration = segments.reduce(0) { $0 + ($1.endTime - $1.startTime) }
        return
            "\(segmentCount) sound section\(segmentCount == 1 ? "" : "s") detected across \(TimeFormatter.string(from: duration))."
            + " Total sound: \(TimeFormatter.string(from: soundDuration))."
    }

    private func startPlaybackTimerIfNeeded() {
        if playbackTimer == nil {
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentTime = self.playbackCoordinator.currentTime
                    self.isPlaying = self.playbackCoordinator.isPlaying
                }
            }
        }
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
                minimumVisibleDuration: minimumVisibleDuration
            )).updatingMinimumVisibleDuration(minimumVisibleDuration)
        self.viewport = viewport

        if let waveformPyramid, waveformPyramidSourceURL == document.url {
            waveform = waveformPyramid.samples(
                for: viewport,
                targetBucketCount: Self.mainWaveformBucketCount
            )
        } else {
            waveform = makeVisibleWaveform(from: document, viewport: viewport)
        }
    }

    private func makeVisibleWaveform(from document: AudioDocument, viewport: WaveformViewport) -> [Float] {
        guard document.sampleRate > 0, !document.samples.isEmpty else { return [] }

        let startIndex = max(Int((viewport.visibleStartTime * document.sampleRate).rounded(.down)), 0)
        let endTime = min(viewport.visibleStartTime + viewport.visibleDuration, document.duration)
        let endIndex = min(
            max(Int((endTime * document.sampleRate).rounded(.up)), startIndex + 1),
            document.samples.count
        )

        return WaveformDownsampler.downsample(
            samples: document.samples[startIndex..<endIndex],
            bucketCount: Self.mainWaveformBucketCount
        )
    }

    private func buildWaveformCache(for document: AudioDocument) {
        let documentURL = document.url
        let samples = document.samples
        let duration = document.duration
        let minimumVisibleDuration = minimumVisibleDuration
        let minimapBucketCount = Self.minimapWaveformBucketCount

        waveformBuildTask?.cancel()
        waveformCachePendingURL = documentURL

        waveformBuildTask = Task.detached(priority: .userInitiated) {
            let pyramid = WaveformPyramid.build(from: samples)
            let fullViewport = WaveformViewport.full(
                duration: duration,
                minimumVisibleDuration: minimumVisibleDuration
            )
            let minimap = pyramid.samples(for: fullViewport, targetBucketCount: minimapBucketCount)

            await MainActor.run {
                guard self.document?.url == documentURL else { return }
                self.waveformPyramid = pyramid
                self.waveformPyramidSourceURL = documentURL
                self.waveformCachePendingURL = nil
                self.minimapWaveform = minimap
                self.updateVisiblePresentation()
            }
        }
    }
}

private enum SupportedTypes {
    static let allowedTypes = ["wav", "mp3", "m4a", "flac"].compactMap {
        UTType(filenameExtension: $0)
    }
}
