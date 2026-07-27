import AudioWaveQuickPreviewCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(model: model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 252, max: 360)
        } detail: {
            LaneStack(model: model)
        }
        .frame(minWidth: 900, minHeight: 480)
        .toolbar { toolbarContent }
        .onAppear {
            model.handleInitialLaunch()
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedFiles(providers: providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Picker("Normalize to", selection: $model.targetLoudnessDBFS) {
                ForEach(AppModel.targetPresets, id: \.self) { target in
                    Text("\(Int(target)) dBFS").tag(target)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Loudness (RMS) target every lane is normalized to.")
        }

        ToolbarItem {
            Button(model.isNormalizeApplied ? "Normalized ✓" : "Apply") {
                model.toggleNormalize()
            }
            .disabled(model.lanes.isEmpty)
            .help("Set each lane's gain so its average loudness meets the target, without clipping.")
        }

        ToolbarItem {
            Button(model.exportLabel) { model.exportLanes() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.canExport)
                .help("Write a gain-adjusted copy of every lane into a folder. Originals are untouched.")
        }
    }

    private func handleDroppedFiles(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    return
                }

                Task { @MainActor in
                    model.add(urls: [url])
                }
            }
        }

        return true
    }
}

// MARK: - File inspector

/// The left sidebar. Checking a row stages that file as a lane; the check is the
/// selection model, so ⌘-click multi-select would only duplicate it.
private struct LibrarySidebar: View {
    @ObservedObject var model: AppModel

    /// The sidebar's own row insets already place "Library" and the rows where
    /// they belong — overriding them just double-indents. Only the header's
    /// trailing edge needs help: the section header runs closer to the panel
    /// edge than its leading inset, leaving "Select All" pinched. Tune this one
    /// value if the two margins still look uneven.
    private static let headerTrailingInset: CGFloat = 10

    var body: some View {
        List {
            Section {
                ForEach(model.filteredEntries) { entry in
                    LibraryRow(
                        entry: entry,
                        isChecked: model.checked.contains(entry.url),
                        onToggle: { model.toggle(entry.url) }
                    )
                    .contextMenu {
                        Button("Remove from Library") { model.remove(url: entry.url) }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Library")
                    Spacer()
                    Button(model.areAllChecked ? "Deselect All" : "Select All") {
                        model.toggleSelectAll()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .disabled(model.entries.isEmpty)
                }
                .padding(.trailing, Self.headerTrailingInset)
                .padding(.bottom, 6)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search")
        .overlay {
            if model.entries.isEmpty {
                ContentUnavailableView(
                    "No Audio Yet",
                    systemImage: "waveform",
                    description: Text("Drop files here or press +.\nwav, mp3, m4a, flac are supported.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button {
                    model.openFilePanel()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 18)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("o")
                .help("Add audio files to the library.")

                Text(model.selectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.bar)
        }
    }
}

private struct LibraryRow: View {
    let entry: LibraryEntry
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .foregroundStyle(isChecked ? Color.accentColor : .secondary)
                .imageScale(.large)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 12.5, weight: isChecked ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(entry.subtitle)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChecked ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Lanes

private struct LaneStack: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(model.lanes) { lane in
                    LaneRow(model: model, lane: lane)
                }
            }
            .padding(14)
        }
        .background(.background.secondary)
        .overlay {
            if model.lanes.isEmpty {
                ContentUnavailableView(
                    "No Lanes",
                    systemImage: "waveform.path",
                    description: Text("Check files in the sidebar and they stack up here.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) { StatusBar(model: model) }
    }
}

private struct LaneRow: View {
    private enum Metrics {
        static let nameColumnWidth: CGFloat = 132
        static let waveformHeight: CGFloat = 60
        static let minimapHeight: CGFloat = 12
        static let peakColumnWidth: CGFloat = 78
    }

    @ObservedObject var model: AppModel
    let lane: Lane

    /// Loaded in the player: keeps the playhead and the card highlight across a
    /// pause, so a paused lane still reads as "the one you are working on".
    private var isCurrent: Bool { model.playingURL == lane.url }
    /// Actually sounding: drives the play/pause icon and the filled button.
    private var isPlaying: Bool { isCurrent && model.isPlaying }

    var body: some View {
        HStack(spacing: 12) {
            playButton

            VStack(alignment: .leading, spacing: 2) {
                Text(lane.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(LibraryRowFormatter.shortTime(lane.duration))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: Metrics.nameColumnWidth, alignment: .leading)

            waveform

            gainStepper

            VStack(alignment: .trailing, spacing: 2) {
                Text(peakText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(lane.isClipping ? .red : .primary)

                Text("PEAK")
                    .font(.system(size: 9.5).weight(.medium))
                    .kerning(0.6)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: Metrics.peakColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isCurrent ? Color.accentColor : .secondary.opacity(0.2), lineWidth: isCurrent ? 2 : 1)
        }
    }

    private var playButton: some View {
        let control = PlaybackControlPresentation.primaryControl(isPlaying: isPlaying)

        return Button {
            model.audition(lane.url)
        } label: {
            Image(systemName: control.systemImageName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isPlaying ? Color.white : .primary)
                .frame(width: 28, height: 28)
                .background(isPlaying ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(lane.document == nil)
        .help(control.toolTip)
        .accessibilityLabel("\(control.accessibilityLabel) \(lane.name)")
    }

    private var waveform: some View {
        VStack(spacing: 4) {
            WaveformView(
                waveform: lane.waveform,
                gainScale: lane.waveformGainScale,
                loadProgress: lane.loadProgress,
                onSeek: { model.seek(lane.url, toViewRatio: $0) },
                onMagnify: { model.zoom(lane.url, scale: $0, anchorRatio: $1) },
                onHorizontalScroll: { model.pan(lane.url, byViewRatio: $0) }
            )
            .frame(height: Metrics.waveformHeight)
            .overlay { TargetGuides(targetDBFS: model.targetLoudnessDBFS) }
            .overlay {
                PlayheadOverlay(
                    ratio: model.playheadRatio(for: lane),
                    lineWidth: 2,
                    offscreenDirection: model.playheadOffscreenDirection(for: lane)
                )
            }
            .overlay(alignment: .topTrailing) {
                if lane.isClipping {
                    Text("CLIP")
                        .font(.system(size: 9, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.red, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(5)
                }
            }
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            // Always present, even at full view: showing it only while zoomed made
            // every lane jump by its height the moment you pinched.
            WaveformMinimapView(
                waveform: lane.minimapWaveform,
                gainScale: lane.waveformGainScale,
                viewport: lane.viewport,
                onJump: { model.jumpViewport(lane.url, toGlobalRatio: $0) }
            )
            .frame(height: Metrics.minimapHeight)
            .overlay { PlayheadOverlay(ratio: model.playheadGlobalRatio(for: lane), lineWidth: 1.5) }
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onTapGesture(count: 2) { model.resetZoom(lane.url) }
            .help("Drag to move the view. Double-click to reset zoom.")
        }
        .frame(maxWidth: .infinity)
    }

    private var gainStepper: some View {
        HStack(spacing: 6) {
            stepperButton("minus", delta: -1)

            Text(String(format: "%+.1f", lane.gainDB))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(lane.gainDB == 0 ? .secondary : .primary)
                .frame(width: 44)
                .help("Total gain for this lane: Normalize plus your trim.")

            stepperButton("plus", delta: 1)
        }
    }

    private func stepperButton(_ systemName: String, delta: Double) -> some View {
        Button {
            model.nudge(lane.url, by: delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
        .disabled(lane.document == nil || !lane.canNudge(by: delta))
    }

    private var peakText: String {
        let value = lane.estimatedPeakDBFS
        return value.isFinite ? String(format: "%.1f", value) : "-∞"
    }
}

/// Dashed lines at the target level, so lanes can be eyeballed against it. The
/// strip draws a peak envelope while the target is RMS, so these mark where the
/// average should sit — not a ceiling.
private struct TargetGuides: View {
    let targetDBFS: Double

    var body: some View {
        GeometryReader { geometry in
            // Matches WaveformView's own 0.46 amplitude budget.
            let amplitude = min(GainCalculations.linearScale(forDB: targetDBFS), 1) * geometry.size.height * 0.46
            let midY = geometry.size.height / 2

            Path { path in
                for lineY in [midY - amplitude, midY + amplitude] {
                    path.move(to: CGPoint(x: 6, y: lineY))
                    path.addLine(to: CGPoint(x: geometry.size.width - 6, y: lineY))
                }
            }
            .stroke(
                .secondary.opacity(0.45),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }
        .allowsHitTesting(false)
    }
}

private struct StatusBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if let progress = model.exportProgress {
                ProgressView(value: progress)
                    .frame(maxWidth: 200)
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Cancel") { model.cancelExport() }
                    .controlSize(.small)
            } else {
                Text(model.statusSummary)
                Text("|").foregroundStyle(.tertiary)
                Text(model.targetSummary)
                    .font(.system(.caption, design: .monospaced))

                if model.clippingLaneCount > 0 {
                    Text("\(model.clippingLaneCount) clipping")
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let folder = model.lastExportFolder {
                Text("Exported to \(folder)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Originals are kept; copies are written to the folder you choose")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
