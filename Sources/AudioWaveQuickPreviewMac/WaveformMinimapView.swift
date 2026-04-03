import AudioWaveQuickPreviewCore
import SwiftUI

struct WaveformMinimapView: View {
    let waveform: [Float]
    let viewport: WaveformViewport?
    let currentTime: Double
    let onJump: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawWaveform(in: &context, size: size)
                drawViewport(in: &context, size: size)
                drawPlayhead(in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard geometry.size.width > 0 else { return }
                        let ratio = gesture.location.x / geometry.size.width
                        onJump(ratio)
                    }
                    .onEnded { gesture in
                        guard geometry.size.width > 0 else { return }
                        let ratio = gesture.location.x / geometry.size.width
                        onJump(ratio)
                    }
            )
        }
    }

    private func drawWaveform(in context: inout GraphicsContext, size: CGSize) {
        guard !waveform.isEmpty else { return }

        var path = Path()
        let midY = size.height / 2
        let bucketWidth = size.width / CGFloat(max(waveform.count, 1))
        let maxAmplitude = size.height * 0.42

        for (index, value) in waveform.enumerated() {
            let amplitude = min(CGFloat(value), 1) * maxAmplitude
            let x = CGFloat(index) * bucketWidth + (bucketWidth / 2)
            path.move(to: CGPoint(x: x, y: midY - amplitude))
            path.addLine(to: CGPoint(x: x, y: midY + amplitude))
        }

        context.stroke(
            path,
            with: .color(.secondary.opacity(0.55)),
            style: StrokeStyle(
                lineWidth: max(min(bucketWidth * 0.5, 1.2), 0.8),
                lineCap: .round
            )
        )
    }

    private func drawViewport(in context: inout GraphicsContext, size: CGSize) {
        guard let viewport, viewport.totalDuration > 0 else { return }

        let startX = size.width * (viewport.visibleStartTime / viewport.totalDuration)
        let width = max(size.width * (viewport.visibleDuration / viewport.totalDuration), 2)
        let rect = CGRect(x: startX, y: 1, width: width, height: max(size.height - 2, 1))

        context.fill(
            Path(roundedRect: rect, cornerRadius: 3),
            with: .color(.accentColor.opacity(0.14))
        )
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 3),
            with: .color(.accentColor.opacity(0.55)),
            lineWidth: 1
        )
    }

    private func drawPlayhead(in context: inout GraphicsContext, size: CGSize) {
        guard let viewport, viewport.totalDuration > 0 else { return }

        let x = size.width * (currentTime / viewport.totalDuration)
        let path = Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }

        context.stroke(path, with: .color(.red.opacity(0.85)), lineWidth: 1.5)
    }
}
