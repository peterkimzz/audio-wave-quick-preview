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
    @State private var showsAdvancedOptions = false

    var body: some View {
        let playbackControl = PlaybackControlPresentation.primaryControl(isPlaying: model.isPlaying)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.fileName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    Text(model.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open Audio") {
                    model.openFilePanel()
                }
                .keyboardShortcut("o")
            }

            HStack(spacing: 12) {
                Button {
                    model.togglePlayback()
                }
                label: {
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
                        .stroke(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isDropTargeted ? 2 : 1)
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

            DisclosureGroup(
                isExpanded: $showsAdvancedOptions,
                content: {
                VStack(alignment: .leading, spacing: 12) {
                    FineTuneControls(model: model)

                    Divider()

                    ParameterSlider(
                        title: "Sensitivity",
                        value: $model.threshold,
                        range: 0.005...0.2,
                        format: "%.3f"
                    )
                    ParameterSlider(
                        title: "Minimum Sound",
                        value: $model.minimumSoundDuration,
                        range: 0.02...1.0,
                        suffix: "s"
                    )
                    ParameterSlider(
                        title: "Merge Silence",
                        value: $model.mergeSilenceDuration,
                        range: 0.02...0.8,
                        suffix: "s"
                    )
                    ParameterSlider(
                        title: "Minimum Visible Span",
                        value: $model.minimumVisibleDuration,
                        range: 5...30,
                        format: "%.0f",
                        suffix: "s"
                    )
                }
                .padding(.top, 10)
                },
                label: {
                    HStack(spacing: 8) {
                        Image(systemName: showsAdvancedOptions ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Advanced Options")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.secondary.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            )
            .onChange(of: model.threshold) { _, _ in model.refreshAnalysis() }
            .onChange(of: model.minimumSoundDuration) { _, _ in model.refreshAnalysis() }
            .onChange(of: model.mergeSilenceDuration) { _, _ in model.refreshAnalysis() }
            .onChange(of: model.minimumVisibleDuration) { _, _ in model.updateMinimumVisibleDuration() }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(minWidth: 900, minHeight: 320)
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
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            Task { @MainActor in
                model.open(url: url)
            }
        }

        return true
    }
}

/// Primary loudness-matching controls: set a target, Normalize to it, compare
/// with Bypass, and Save. Manual per-dB gain lives in Advanced Options.
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

                Slider(
                    value: $model.targetLoudnessDBFS,
                    in: GainCalculations.minTargetLoudnessDBFS...GainCalculations.maxTargetLoudnessDBFS,
                    step: 1
                )
                .frame(minWidth: 160)
                .disabled(!model.hasDocument)
                .help("Target loudness. Negative only (0 = digital max); typical −24 … −12.")

                Text("\(Int(model.targetLoudnessDBFS)) dBFS")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .trailing)

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
                Text("Loudness: \(loudnessText)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)

                if model.isClipping {
                    Text("Too loud to save — max safe gain \(String(format: "%+.1f", model.maxSafeGainDB)) dB")
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
}

/// Manual by-ear fine-tune, shown under Advanced Options. It layers a ± offset
/// on top of the gain that Normalize set, rather than replacing it.
private struct FineTuneControls: View {
    @ObservedObject var model: AppModel

    private var offsetBinding: Binding<Double> {
        Binding(get: { model.offsetDB }, set: { model.setOffset($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("Fine-tune")
                    .font(.headline)

                Slider(value: offsetBinding, in: GainCalculations.minOffsetDB...GainCalculations.maxOffsetDB, step: GainCalculations.stepDB)
                    .frame(minWidth: 160)
                    .disabled(!model.hasDocument)
                    .help("Nudge the loudness up or down by ear, on top of Normalize.")

                Text("\(signed(model.offsetDB)) dB")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)

                Button("0 dB Reset") { model.resetGain() }
                    .disabled(!model.hasDocument || (model.normalizeBaseDB == 0 && model.offsetDB == 0))
                    .help("Back to the original level (clears Normalize and fine-tune).")

                Spacer()

                Text("Total gain: \(signed(model.gainDB)) dB   Est. peak: \(peakText)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func signed(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    private var peakText: String {
        let value = model.estimatedPeakDBFS
        return value.isFinite ? String(format: "%.1f dBFS", value) : "-∞ dBFS"
    }
}

private struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"
    var suffix = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(String(format: format, value) + suffix)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range)
        }
    }
}
