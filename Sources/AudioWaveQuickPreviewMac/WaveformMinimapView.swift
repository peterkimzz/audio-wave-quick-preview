import AudioWaveQuickPreviewCore
import SwiftUI

struct WaveformMinimapView: View {
    let waveform: [Float]
    let gainScale: Float
    let viewport: WaveformViewport?
    let onJump: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawWaveform(in: &context, size: size)
                drawViewport(in: &context, size: size)
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
            let amplitude = min(CGFloat(value * gainScale), 1) * maxAmplitude
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
        // At full view the rect would cover the whole strip, which reads as a
        // selection rather than "you are already seeing everything". The minimap
        // itself stays visible so the lane height never shifts.
        guard viewport.visibleDuration < viewport.totalDuration else { return }

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
}
