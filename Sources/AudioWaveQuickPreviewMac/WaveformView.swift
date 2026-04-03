import AudioWaveQuickPreviewCore
import SwiftUI

struct WaveformView: View {
    let waveform: [Float]
    let segments: [SoundSegment]
    let showsDetectedRegions: Bool
    let duration: Double
    let currentTime: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    drawSegments(in: &context, size: size)
                    drawWaveform(in: &context, size: size)
                    drawPlayhead(in: &context, size: size)
                }

                if waveform.isEmpty {
                    ContentUnavailableView(
                        "Drop or Open Audio",
                        systemImage: "waveform",
                        description: Text("wav, mp3, m4a, flac files are supported in v1.")
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard geometry.size.width > 0 else { return }
                        let ratio = gesture.location.x / geometry.size.width
                        onSeek(ratio)
                    }
                    .onEnded { gesture in
                        guard geometry.size.width > 0 else { return }
                        let ratio = gesture.location.x / geometry.size.width
                        onSeek(ratio)
                    }
            )
        }
    }

    private func drawSegments(in context: inout GraphicsContext, size: CGSize) {
        guard showsDetectedRegions, duration > 0 else { return }

        for segment in segments {
            let startX = size.width * (segment.startTime / duration)
            let endX = size.width * (segment.endTime / duration)
            let rect = CGRect(x: startX, y: 0, width: max(endX - startX, 2), height: size.height)

            context.fill(
                Path(roundedRect: rect, cornerRadius: 6),
                with: .color(.accentColor.opacity(0.18))
            )
        }
    }

    private func drawWaveform(in context: inout GraphicsContext, size: CGSize) {
        guard !waveform.isEmpty else { return }

        var path = Path()
        let midY = size.height / 2
        let bucketWidth = size.width / CGFloat(max(waveform.count, 1))
        let maxAmplitude = size.height * 0.36

        for (index, value) in waveform.enumerated() {
            let amplitude = min(CGFloat(value), 1) * maxAmplitude
            let x = CGFloat(index) * bucketWidth + (bucketWidth / 2)
            path.move(to: CGPoint(x: x, y: midY - amplitude))
            path.addLine(to: CGPoint(x: x, y: midY + amplitude))
        }

        context.stroke(
            path,
            with: .color(.primary.opacity(0.8)),
            style: StrokeStyle(
                lineWidth: max(min(bucketWidth * 0.55, 1.6), 1),
                lineCap: .round
            )
        )

        let baseline = Path { baseline in
            baseline.move(to: CGPoint(x: 0, y: midY))
            baseline.addLine(to: CGPoint(x: size.width, y: midY))
        }

        context.stroke(baseline, with: .color(.secondary.opacity(0.12)), lineWidth: 1)
    }

    private func drawPlayhead(in context: inout GraphicsContext, size: CGSize) {
        guard duration > 0 else { return }

        let x = size.width * (currentTime / duration)
        let line = Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }

        context.stroke(line, with: .color(.red.opacity(0.85)), lineWidth: 2)
    }
}
