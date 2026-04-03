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
    @Published var statusMessage = "Open an audio file to inspect where sound is present."
    @Published var errorMessage: String?

    private let playbackCoordinator = PlaybackCoordinator()
    private var document: AudioDocument?
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
        let clampedRatio = min(max(ratio, 0), 1)
        let time = clampedRatio * duration
        playbackCoordinator.seek(to: time)
        currentTime = time
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

        waveform = result.waveform
        segments = result.segments
        statusMessage = makeStatusMessage(segmentCount: result.segments.count, duration: document.duration)
    }

    private func makeStatusMessage(segmentCount: Int, duration: Double) -> String {
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
}

private enum SupportedTypes {
    static let allowedTypes = ["wav", "mp3", "m4a", "flac"].compactMap {
        UTType(filenameExtension: $0)
    }
}
