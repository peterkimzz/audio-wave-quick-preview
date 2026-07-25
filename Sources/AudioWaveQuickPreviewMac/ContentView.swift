import AudioWaveQuickPreviewCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum PlaybackButtonStyle {
        static let iconFont: Font = .system(size: 15, weight: .semibold)
    }

    @ObservedObject var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        let playbackControl = PlaybackControlPresentation.primaryControl(isPlaying: model.isPlaying)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.fileName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Button("Open Audio") {
                    model.openFilePanel()
                }
                .keyboardShortcut("o")
            }

            HStack(spacing: 12) {
                Button {
                    model.togglePlayback()
                } label: {
                    ZStack {
                        Image(systemName: "play.fill")
                            .opacity(playbackControl.systemImageName == "play.fill" ? 1 : 0)

                        Image(systemName: "pause.fill")
                            .opacity(playbackControl.systemImageName == "pause.fill" ? 1 : 0)
                    }
                    .font(PlaybackButtonStyle.iconFont)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.duration == 0)
                .keyboardShortcut(.space, modifiers: [])
                .help(playbackControl.toolTip)
                .accessibilityLabel(playbackControl.accessibilityLabel)

                Button("-10s") {
                    model.seekBackwardByKeyboardInterval()
                }
                .buttonStyle(.bordered)
                .disabled(model.duration == 0)

                Button("+10s") {
                    model.seekForwardByKeyboardInterval()
                }
                .buttonStyle(.bordered)
                .disabled(model.duration == 0)

                Text(TimeFormatter.string(from: model.currentTime))
                    .font(.system(.body, design: .monospaced))

                Text("/")
                    .foregroundStyle(.secondary)

                Text(TimeFormatter.string(from: model.duration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Go to Playhead") {
                    model.centerOnPlayhead()
                }
                .disabled(model.viewport == nil)

                Button("Reset Zoom") {
                    model.resetZoom()
                }
                .disabled(model.viewport == nil)
            }

            GainControls(model: model)

            VStack(spacing: 7) {
                WaveformView(
                    waveform: model.waveform,
                    gainScale: model.waveformGainScale,
                    viewport: model.viewport,
                    duration: model.duration,
                    currentTime: model.currentTime,
                    onSeek: model.seek(to:),
                    onMagnify: model.zoomWaveform(scale:anchorRatio:),
                    onHorizontalScroll: model.panWaveform(byViewRatio:)
                )
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.15),
                            lineWidth: isDropTargeted ? 2 : 1)
                }

                WaveformMinimapView(
                    waveform: model.minimapWaveform,
                    gainScale: model.waveformGainScale,
                    viewport: model.viewport,
                    currentTime: model.currentTime,
                    onJump: model.jumpViewport(toGlobalRatio:)
                )
                .frame(height: 18)
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(minWidth: 900, minHeight: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            model.handleInitialLaunch()
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedFiles(providers: providers)
        }
    }

    private func handleDroppedFiles(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                let url = URL(dataRepresentation: data, relativeTo: nil)
            else {
                return
            }

            Task { @MainActor in
                model.open(url: url)
            }
        }

        return true
    }
}

/// Shared column widths so the Target and Fine-tune rows line up.
private enum GainRowMetrics {
    static let labelWidth: CGFloat = 74
    static let sliderWidth: CGFloat = 200
    static let valueWidth: CGFloat = 74
}

/// Loudness controls: set a target, Normalize to it, nudge by ear with
/// Fine-tune, compare with Bypass, and Save.
private struct GainControls: View {
    @ObservedObject var model: AppModel

    private var bypassBinding: Binding<Bool> {
        Binding(get: { model.isBypassed }, set: { _ in model.toggleBypass() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("Target")
                    .font(.headline)
                    .frame(width: GainRowMetrics.labelWidth, alignment: .leading)

                Slider(
                    value: $model.targetLoudnessDBFS,
                    in: GainCalculations.minTargetLoudnessDBFS...GainCalculations.maxTargetLoudnessDBFS,
                    step: 1
                )
                .frame(width: GainRowMetrics.sliderWidth)
                .disabled(!model.hasDocument)
                .help("Target loudness. Negative only (0 = digital max); typical −24 … −12.")

                Text("\(Int(model.targetLoudnessDBFS)) dBFS")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: GainRowMetrics.valueWidth, alignment: .trailing)

                Button("Normalize") { model.normalizeToTarget() }
                    .disabled(!model.hasDocument)
                    .help("Set gain so the average loudness (RMS) meets the target, without clipping.")

                Toggle("Bypass", isOn: bypassBinding)
                    .toggleStyle(.button)
                    .disabled(!model.hasDocument)
                    .help("Listen to the original without changing the save gain.")

                Spacer()

                Button("Save As…") { model.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!model.canSave)
            }

            FineTuneControls(model: model)

            statusRow
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if let progress = model.exportProgress {
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .frame(maxWidth: 220)
                Text("\(Int(progress * 100))%")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Cancel") { model.cancelExport() }
                    .controlSize(.small)
            }
        } else if model.hasDocument {
            HStack(spacing: 12) {
                Text(
                    "Loudness: \(loudnessText) · Total gain: \(String(format: "%+.1f", model.gainDB)) dB"
                        + " · Est. peak: \(peakText)"
                )
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)

                if model.isClipping {
                    Text("Too loud to save — max safe gain \(String(format: "%+.1f", model.maxSafeGainDB)) dB")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                } else if model.isPeakLimited {
                    Text("Peak-limited — can't reach the target without clipping")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                } else if let saved = model.lastSavedPath {
                    Text("Saved to \(saved)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var loudnessText: String {
        let value = model.estimatedLoudnessDBFS
        return value.isFinite ? String(format: "%.1f dBFS", value) : "-∞ dBFS"
    }

    private var peakText: String {
        let value = model.estimatedPeakDBFS
        return value.isFinite ? String(format: "%.1f dBFS", value) : "-∞ dBFS"
    }
}

/// Manual by-ear fine-tune. It layers a ± offset on top of the gain that
/// Normalize set, rather than replacing it.
private struct FineTuneControls: View {
    @ObservedObject var model: AppModel

    private var offsetBinding: Binding<Double> {
        Binding(get: { model.offsetDB }, set: { model.setOffset($0) })
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Fine-tune")
                .font(.headline)
                .frame(width: GainRowMetrics.labelWidth, alignment: .leading)

            Slider(
                value: offsetBinding, in: GainCalculations.minOffsetDB...GainCalculations.maxOffsetDB,
                step: GainCalculations.stepDB
            )
            .frame(width: GainRowMetrics.sliderWidth)
            .disabled(!model.hasDocument)
            .help("Nudge the loudness up or down by ear, on top of Normalize.")

            Text(String(format: "%+.1f dB", model.offsetDB))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: GainRowMetrics.valueWidth, alignment: .trailing)

            Button("0 dB Reset") { model.resetGain() }
                .disabled(!model.hasDocument || (model.normalizeBaseDB == 0 && model.offsetDB == 0))
                .help("Back to the original level (clears Normalize and fine-tune).")

            Spacer()
        }
    }
}
