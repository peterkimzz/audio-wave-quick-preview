public enum KeyboardShortcutAction: Sendable, Equatable {
    case togglePlayback
    case seekBackward
    case seekForward
}

public enum KeyboardShortcutResolver {
    public static func action(for key: Character, hasModifiers: Bool) -> KeyboardShortcutAction? {
        guard !hasModifiers else { return nil }
        if key == " " {
            return .togglePlayback
        }
        return nil
    }

    public static func action(forKeyCode keyCode: UInt16, hasModifiers: Bool) -> KeyboardShortcutAction? {
        guard !hasModifiers else { return nil }

        switch keyCode {
        case 49:
            return .togglePlayback
        case 123:
            return .seekBackward
        case 124:
            return .seekForward
        default:
            return nil
        }
    }
}
