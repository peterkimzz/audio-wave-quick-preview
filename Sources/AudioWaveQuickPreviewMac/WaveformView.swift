import SwiftUI

struct WaveformView: View {
    let waveform: [Float]
    let gainScale: Float
    /// Progress of the streaming analysis, or nil when nothing is loading.
    let loadProgress: Double?
    let onSeek: (Double) -> Void
    let onMagnify: (_ scale: Double, _ anchorRatio: Double) -> Void
    let onHorizontalScroll: (_ deltaRatio: Double) -> Void

    var body: some View {
        ZStack {
            Canvas { context, size in
                drawWaveform(in: &context, size: size)
            }

            if let loadProgress {
                ProgressView(value: loadProgress) {
                    Text("Analyzing audio…")
                }
                .progressViewStyle(.linear)
                .frame(maxWidth: 240)
                .padding(.horizontal, 24)
            } else if waveform.isEmpty {
                ContentUnavailableView(
                    "Drop or Open Audio",
                    systemImage: "waveform",
                    description: Text("wav, mp3, m4a, flac files are supported in v1.")
                )
            }

            WaveformInteractionView(
                onMagnify: onMagnify,
                onHorizontalScroll: onHorizontalScroll,
                onSeek: onSeek
            )
        }
        .contentShape(Rectangle())
    }

    private func drawWaveform(in context: inout GraphicsContext, size: CGSize) {
        guard !waveform.isEmpty else { return }

        var path = Path()
        let midY = size.height / 2
        let bucketWidth = size.width / CGFloat(max(waveform.count, 1))
        let maxAmplitude = size.height * 0.46

        for (index, value) in waveform.enumerated() {
            let amplitude = min(CGFloat(value * gainScale), 1) * maxAmplitude
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
}
