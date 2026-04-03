public enum PlaybackNavigation {
    public static func shiftedTime(
        currentTime: Double,
        duration: Double,
        delta: Double
    ) -> Double {
        let clampedDuration = max(duration, 0)
        let candidate = currentTime + delta
        return min(max(candidate, 0), clampedDuration)
    }
}
