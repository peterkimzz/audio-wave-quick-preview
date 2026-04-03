public struct PlaybackControlPresentation: Sendable, Equatable {
    public let systemImageName: String
    public let accessibilityLabel: String
    public let toolTip: String

    public init(systemImageName: String, accessibilityLabel: String, toolTip: String) {
        self.systemImageName = systemImageName
        self.accessibilityLabel = accessibilityLabel
        self.toolTip = toolTip
    }

    public static func primaryControl(isPlaying: Bool) -> PlaybackControlPresentation {
        if isPlaying {
            return PlaybackControlPresentation(
                systemImageName: "pause.fill",
                accessibilityLabel: "Pause",
                toolTip: "Pause"
            )
        }

        return PlaybackControlPresentation(
            systemImageName: "play.fill",
            accessibilityLabel: "Play",
            toolTip: "Play"
        )
    }
}
