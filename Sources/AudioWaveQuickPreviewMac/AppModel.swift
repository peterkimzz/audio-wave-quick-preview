import AudioWaveQuickPreviewCore
import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var fileName = "No audio selected"
    @Published var waveform: [Float] = []
    @Published var segments: [SoundSegment] = []
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var threshold: Double = 0.025
    @Published var minimumSoundDuration: Double = 0.12
    @Published var mergeSilenceDuration: Double = 0.08
    @Published var waveformHeight: Double = 120
    @Published var showsDetectedRegions = false
    @Published var minimumVisibleDuration: Double = 5
    @Published private(set) var viewport: WaveformViewport?
    @Published var statusMessage = "Open an audio file to inspect where sound is present."
    @Published var errorMessage: String?

    private let playbackCoordinator = PlaybackCoordinator()
    private var document: AudioDocument?
    private var detectedSegments: [SoundSegment] = []
    private var playbackTimer: Timer?

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
            fileName = document.fileName
            duration = document.duration
            currentTime = 0
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

    func refreshAnalysis() {
        guard let document else {
            waveform = []
            segments = []
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
                waveformBucketCount: 700
            )
        )

        detectedSegments = result.segments
        statusMessage = makeStatusMessage(segments: result.segments, duration: document.duration)
        updateVisiblePresentation()
    }

    private func makeStatusMessage(segments: [SoundSegment], duration: Double) -> String {
        let segmentCount = segments.count
        if segmentCount == 0 {
            return "No sound sections detected at the current sensitivity."
        }

        let soundDuration = segments.reduce(0) { $0 + ($1.endTime - $1.startTime) }
        return "\(segmentCount) sound section\(segmentCount == 1 ? "" : "s") detected across \(TimeFormatter.string(from: duration)). Highlighted regions are clickable."
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
            segments = []
            return
        }

        let viewport = (self.viewport ?? .full(
            duration: document.duration,
            minimumVisibleDuration: minimumVisibleDuration
        )).updatingMinimumVisibleDuration(minimumVisibleDuration)
        self.viewport = viewport

        waveform = makeVisibleWaveform(from: document, viewport: viewport)
        segments = makeVisibleSegments(from: detectedSegments, viewport: viewport)
    }

    private func makeVisibleWaveform(from document: AudioDocument, viewport: WaveformViewport) -> [Float] {
        guard document.sampleRate > 0, !document.samples.isEmpty else { return [] }

        let startIndex = max(Int((viewport.visibleStartTime * document.sampleRate).rounded(.down)), 0)
        let endTime = min(viewport.visibleStartTime + viewport.visibleDuration, document.duration)
        let endIndex = min(
            max(Int((endTime * document.sampleRate).rounded(.up)), startIndex + 1),
            document.samples.count
        )

        let visibleSamples = Array(document.samples[startIndex..<endIndex])
        return WaveformDownsampler.downsample(samples: visibleSamples, bucketCount: 900)
    }

    private func makeVisibleSegments(from segments: [SoundSegment], viewport: WaveformViewport) -> [SoundSegment] {
        let visibleEndTime = viewport.visibleStartTime + viewport.visibleDuration

        return segments.compactMap { segment in
            let start = max(segment.startTime, viewport.visibleStartTime)
            let end = min(segment.endTime, visibleEndTime)

            guard end > start else { return nil }
            return SoundSegment(startTime: start, endTime: end)
        }
    }
}

private enum SupportedTypes {
    static let allowedTypes = ["wav", "mp3", "m4a", "flac"].compactMap {
        UTType(filenameExtension: $0)
    }
}
