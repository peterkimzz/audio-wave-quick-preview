import AppKit
import AudioWaveQuickPreviewCore
import SwiftUI

struct WaveformInteractionView: NSViewRepresentable {
    var onMagnify: (_ scale: Double, _ anchorRatio: Double) -> Void
    var onHorizontalScroll: (_ deltaRatio: Double) -> Void
    var onSeek: (_ viewRatio: Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMagnify: onMagnify,
            onHorizontalScroll: onHorizontalScroll,
            onSeek: onSeek
        )
    }

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        nsView.coordinator = context.coordinator
    }
}

final class InteractionNSView: NSView {
    weak var coordinator: WaveformInteractionView.Coordinator?
    private var scrollAxis = ScrollAxisLatch()
    private lazy var magnificationRecognizer = NSMagnificationGestureRecognizer(
        target: self,
        action: #selector(handleMagnification(_:))
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addGestureRecognizer(magnificationRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func scrollWheel(with event: NSEvent) {
        let isHorizontal = scrollAxis.isHorizontal(
            deltaX: Double(event.scrollingDeltaX),
            deltaY: Double(event.scrollingDeltaY),
            phase: Self.latchPhase(for: event)
        )

        guard bounds.width > 0, isHorizontal else {
            super.scrollWheel(with: event)
            return
        }

        let deltaRatio = Double((-event.scrollingDeltaX) / bounds.width)
        coordinator?.onHorizontalScroll(deltaRatio)
    }

    private static func latchPhase(for event: NSEvent) -> ScrollAxisLatch.Phase {
        switch event.phase {
        case .began: .began
        case .ended, .cancelled: .ended
        default: .changed
        }
    }

    override func mouseDown(with event: NSEvent) {
        seek(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        seek(with: event)
    }

    @objc private func handleMagnification(_ recognizer: NSMagnificationGestureRecognizer) {
        guard bounds.width > 0 else { return }
        let location = recognizer.location(in: self)
        let anchorRatio = min(max(location.x / bounds.width, 0), 1)
        coordinator?.onMagnify(Double(1 + recognizer.magnification), Double(anchorRatio))
        recognizer.magnification = 0
    }

    private func seek(with event: NSEvent) {
        guard bounds.width > 0 else { return }
        let location = convert(event.locationInWindow, from: nil)
        let ratio = min(max(location.x / bounds.width, 0), 1)
        coordinator?.onSeek(Double(ratio))
    }
}

extension WaveformInteractionView {
    final class Coordinator: NSObject {
        let onMagnify: (_ scale: Double, _ anchorRatio: Double) -> Void
        let onHorizontalScroll: (_ deltaRatio: Double) -> Void
        let onSeek: (_ viewRatio: Double) -> Void

        init(
            onMagnify: @escaping (_ scale: Double, _ anchorRatio: Double) -> Void,
            onHorizontalScroll: @escaping (_ deltaRatio: Double) -> Void,
            onSeek: @escaping (_ viewRatio: Double) -> Void
        ) {
            self.onMagnify = onMagnify
            self.onHorizontalScroll = onHorizontalScroll
            self.onSeek = onSeek
        }
    }
}
