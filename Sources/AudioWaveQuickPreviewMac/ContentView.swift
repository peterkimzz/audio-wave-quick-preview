import AudioWaveQuickPreviewCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            FolderSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 252, max: 360)
        } detail: {
            LaneStack(model: model)
        }
        .frame(minWidth: 900, minHeight: 480)
        .toolbar { toolbarContent }
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
            .help("Quick RMS target for the selected folder.")
        }

        ToolbarItem {
            Button(model.isNormalizeApplied ? "Normalized ✓" : "Apply") {
                model.toggleNormalize()
            }
            .disabled(model.lanes.isEmpty)
            .help("Preview the selected folder target on its loaded files without exporting them.")
        }
    }
}

// MARK: - Folder inspector

/// The left sidebar is the app's navigation. Selecting a saved folder loads all
/// of its supported audio files into lanes immediately.
private struct FolderSidebar: View {
    @ObservedObject var model: AppModel

    private static let headerTrailingInset: CGFloat = 10

    var body: some View {
        List {
            Section {
                ForEach(model.folders) { folder in
                    FolderRow(
                        folder: folder,
                        isSelected: model.selectedFolderID == folder.id,
                        onSelect: { model.selectFolder(folder.id) },
                        onChooseFolder: { model.chooseFolder(for: folder.id) }
                    )
                    .contextMenu {
                        Button("Choose Folder Location…") { model.chooseFolder(for: folder.id) }
                        if model.folders.count > 1 {
                            Divider()
                            Button("Remove Folder", role: .destructive) {
                                model.removeFolder(folder.id)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Folders")
                    Spacer()
                    Button {
                        model.addFolder()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Add a folder")
                }
                .padding(.trailing, Self.headerTrailingInset)
                .padding(.bottom, 6)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct FolderRow: View {
    let folder: AudioFolder
    let isSelected: Bool
    let onSelect: () -> Void
    let onChooseFolder: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "folder.fill" : "folder")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Text(detailText)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Button(action: onChooseFolder) {
                Image(systemName: folder.folderURL == nil ? "folder.badge.plus" : "folder.badge.gearshape")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help(folder.folderURL == nil ? "Choose folder location" : "Change folder location")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private var detailText: String {
        let target = String(format: "%.1f", folder.targetLoudnessDBFS)
        if let folderName = folder.folderName {
            return folderName + " · " + target + " dBFS"
        }
        return "No location · " + target + " dBFS"
    }
}

// MARK: - Lanes

private struct LaneStack: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            FolderHeader(model: model)

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
                        model.selectedFolder?.folderURL == nil ? "Choose a Folder" : "Folder is Empty",
                        systemImage: model.selectedFolder?.folderURL == nil ? "folder.badge.plus" : "waveform.path",
                        description: Text(emptyDescription)
                    )
                }
            }
            .safeAreaInset(edge: .bottom) { StatusBar(model: model) }
        }
    }

    private var emptyDescription: String {
        if model.selectedFolder?.folderURL == nil {
            return "Choose a location for \(model.selectedFolder?.name ?? "this folder") to load its audio files."
        }
        return "Put supported audio files directly in this folder, then use Refresh or Normalize & Export."
    }
}

private struct FolderHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.selectedFolder?.name ?? "Folders")
                    .font(.system(size: 15, weight: .semibold))
                Text(folderText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Text("Target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: $model.targetLoudnessDBFS,
                    in: GainCalculations.minTargetLoudnessDBFS...GainCalculations.maxTargetLoudnessDBFS,
                    step: GainCalculations.stepDB
                )
                .frame(width: 130)
                Text(String(format: "%+.1f dBFS", model.targetLoudnessDBFS))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 76, alignment: .trailing)
                    .help("Saved RMS target for this folder")
            }

            Button("Choose Location…") {
                model.chooseFolderForSelectedFolder()
            }
            .disabled(model.selectedFolder == nil)

            Button("Refresh") {
                model.scanSelectedFolder()
            }
            .disabled(model.selectedFolder?.folderURL == nil || model.isProcessingFolder)

            Button(model.processFolderLabel) {
                model.processSelectedFolder()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canProcessFolder)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var folderText: String {
        if let folder = model.selectedFolder?.folderURL {
            return "Input: \(folder.path)  ·  Output: \(folder.appendingPathComponent("Normalized").path)"
        }
        return "Folder location not connected"
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

                Text(AudioRowFormatter.shortTime(lane.duration))
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
            } else if model.isProcessingFolder {
                ProgressView()
                Text("Analyzing folder files…")
                    .foregroundStyle(.secondary)
                Button("Cancel") { model.cancelFolderProcessing() }
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
                Text(model.outputHint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
