import AudioWaveQuickPreviewCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var isDropTargeted = false
    @State private var showsAdvancedOptions = false

    var body: some View {
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
                Button(model.isPlaying ? "Pause" : "Play") {
                    model.togglePlayback()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.duration == 0)
                .keyboardShortcut(.space, modifiers: [])

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

            WaveformView(
                waveform: model.waveform,
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

            DisclosureGroup(
                isExpanded: $showsAdvancedOptions,
                content: {
                VStack(alignment: .leading, spacing: 12) {
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
