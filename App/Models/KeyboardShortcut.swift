import Foundation

/// 全局快捷键的稳定值表示。
///
/// 持久化时保存物理 keyCode 与 modifier mask,不依赖当前键盘布局或本地化字符串。
/// 显示文本运行时根据 keyCode 映射生成,仅用于 UI。
public struct KeyboardShortcut: Sendable, Hashable, Codable {
    public let keyCode: UInt32
    public let modifierFlags: ModifierFlags

    public init(keyCode: UInt32, modifierFlags: ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    public struct ModifierFlags: OptionSet, Sendable, Hashable, Codable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let command = ModifierFlags(rawValue: 1 << 8)
        public static let shift = ModifierFlags(rawValue: 1 << 9)
        public static let option = ModifierFlags(rawValue: 1 << 11)
        public static let control = ModifierFlags(rawValue: 1 << 12)

        public var carbonMask: UInt32 {
            var mask: UInt32 = 0
            if contains(.command) { mask |= 1 << 8 }
            if contains(.shift) { mask |= 1 << 9 }
            if contains(.option) { mask |= 1 << 11 }
            if contains(.control) { mask |= 1 << 12 }
            return mask
        }

        public var carbonModifierFlags: UInt32 {
            var result: UInt32 = 0
            if contains(.command) { result |= 256 }
            if contains(.shift) { result |= 512 }
            if contains(.option) { result |= 2048 }
            if contains(.control) { result |= 4096 }
            return result
        }
    }

    /// 是否构成有效快捷键。
    ///
    /// 校验条件:
    /// - 至少一个修饰键。
    /// - keyCode 在已知 USB HID 键码范围内(0..126 常规键,F-keys 等)。
    ///   keyCode == 0 是 macOS 虚拟键码中的 A 键,合法。
    public var isValid: Bool {
        guard !modifierFlags.isEmpty else { return false }
        return Self.isKnownKeyCode(keyCode)
    }

    /// 简单键码白名单:0..126(HID Layout 常规键 + F1..F12 + 方向键),不排除 0。
    public static func isKnownKeyCode(_ keyCode: UInt32) -> Bool {
        keyCode <= 126
    }

    public var displayText: String {
        var parts: [String] = []
        if modifierFlags.contains(.control) { parts.append("⌃") }
        if modifierFlags.contains(.option) { parts.append("⌥") }
        if modifierFlags.contains(.shift) { parts.append("⇧") }
        if modifierFlags.contains(.command) { parts.append("⌘") }
        parts.append(KeyCodes.displayName(for: keyCode))
        return parts.joined()
    }

    public static let `default` = KeyboardShortcut(
        keyCode: KeyCodes.space,
        modifierFlags: .option
    )
}

public enum KeyCodes {
    public static let space: UInt32 = 49

    public static func displayName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 53: return "⎋"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if keyCode >= 0 && keyCode <= 25 {
                let letters: [Character] = [
                    "A","S","D","F","H","G","Z","X","C","V",
                    "§","B","Q","W","E","R","Y","T","Y","U",
                    "I","O","P","[","]"
                ]
                if Int(keyCode) < letters.count {
                    return String(letters[Int(keyCode)])
                }
            }
            if keyCode >= 18 && keyCode <= 29 {
                let numbers = ["1","2","3","4","5","6","7","8","9","0"]
                let index = Int(keyCode) - 18
                if index >= 0 && index < numbers.count {
                    return numbers[index]
                }
            }
            return "Key\(keyCode)"
        }
    }
}
