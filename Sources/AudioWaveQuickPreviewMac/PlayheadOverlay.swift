import AudioWaveQuickPreviewCore
import SwiftUI

/// The playhead lives outside the waveform `Canvas` on purpose: sharing one
/// canvas meant a 1px playhead move rebuilt every waveform path segment, 20×
/// a second. Here only this overlay's layout is recomputed.
struct PlayheadOverlay: View {
    /// Position within the visible span. Nil hides the line (playhead offscreen).
    let ratio: Double?
    let lineWidth: CGFloat
    var offscreenDirection: OffscreenIndicatorDirection?

    init(
        ratio: Double?,
        lineWidth: CGFloat,
        offscreenDirection: OffscreenIndicatorDirection? = nil
    ) {
        self.ratio = ratio
        self.lineWidth = lineWidth
        self.offscreenDirection = offscreenDirection
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let ratio {
                    Rectangle()
                        .fill(.red.opacity(0.85))
                        .frame(width: lineWidth)
                        .offset(x: (geometry.size.width * ratio) - (lineWidth / 2))
                }

                if let offscreenDirection {
                    HStack {
                        if offscreenDirection == .left {
                            arrow("<--")
                        }

                        Spacer()

                        if offscreenDirection == .right {
                            arrow("-->")
                        }
                    }
                    .padding(12)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        // The waveform's scroll/click handling sits underneath this overlay.
        .allowsHitTesting(false)
    }

    private func arrow(_ text: String) -> some View {
        Text(text)
            .font(.system(.headline, design: .monospaced))
            .foregroundStyle(.red)
    }
}
