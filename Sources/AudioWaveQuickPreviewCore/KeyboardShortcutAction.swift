public enum KeyboardShortcutAction: Sendable, Equatable {
    case togglePlayback
}

public enum KeyboardShortcutResolver {
    public static func action(for key: Character, hasModifiers: Bool) -> KeyboardShortcutAction? {
        guard !hasModifiers else { return nil }
        if key == " " {
            return .togglePlayback
        }
        return nil
    }
}
