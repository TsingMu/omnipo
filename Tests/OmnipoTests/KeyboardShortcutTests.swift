import XCTest
@testable import Omnipo

final class KeyboardShortcutTests: XCTestCase {

    func test_defaultShortcut_isOptionSpace() {
        let shortcut = KeyboardShortcut.default
        XCTAssertEqual(shortcut.keyCode, 49)
        XCTAssertEqual(shortcut.modifierFlags, .option)
    }

    func test_isValid_rejectsEmptyModifier() {
        let shortcut = KeyboardShortcut(keyCode: 49, modifierFlags: [])
        XCTAssertFalse(shortcut.isValid)
    }

    func test_isValid_acceptsAtLeastOneModifierAndNonZeroKeyCode() {
        let shortcut = KeyboardShortcut.default
        XCTAssertTrue(shortcut.isValid)
    }

    func test_isValid_acceptsKeyCodeZeroAsLetterA() {
        // macOS 虚拟键码 0 是 A 键,不应被当作无效排除。
        let shortcut = KeyboardShortcut(keyCode: 0, modifierFlags: .option)
        XCTAssertTrue(shortcut.isValid, "Option+A should be a valid shortcut")
    }

    func test_isValid_rejectsKeyCodeAboveKnownRange() {
        let shortcut = KeyboardShortcut(keyCode: 200, modifierFlags: .option)
        XCTAssertFalse(shortcut.isValid)
    }

    func test_displayText_includesSymbolAndKey() {
        let shortcut = KeyboardShortcut.default
        XCTAssertTrue(shortcut.displayText.contains("⌥"))
        XCTAssertTrue(shortcut.displayText.contains("Space"))
    }

    func test_displayText_includesAllModifiersInStableOrder() {
        let shortcut = KeyboardShortcut(
            keyCode: 0,
            modifierFlags: [.command, .option, .shift, .control]
        )
        let text = shortcut.displayText
        let controlIndex = text.distance(from: text.startIndex, to: text.range(of: "⌃")!.lowerBound)
        let optionIndex = text.distance(from: text.startIndex, to: text.range(of: "⌥")!.lowerBound)
        let shiftIndex = text.distance(from: text.startIndex, to: text.range(of: "⇧")!.lowerBound)
        let commandIndex = text.distance(from: text.startIndex, to: text.range(of: "⌘")!.lowerBound)
        XCTAssertLessThan(controlIndex, optionIndex)
        XCTAssertLessThan(optionIndex, shiftIndex)
        XCTAssertLessThan(shiftIndex, commandIndex)
    }

    func test_modifierFlags_carbonMask_setsExpectedBits() {
        let flags: KeyboardShortcut.ModifierFlags = [.command, .option]
        let mask = flags.carbonModifierFlags
        XCTAssertTrue(mask & 256 != 0, "command bit should be set")
        XCTAssertTrue(mask & 2048 != 0, "option bit should be set")
        XCTAssertEqual(mask & 512, 0, "shift bit should be unset")
        XCTAssertEqual(mask & 4096, 0, "control bit should be unset")
    }

    func test_serialization_roundTrips() throws {
        let original = KeyboardShortcut(keyCode: 11, modifierFlags: [.command, .shift])
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(KeyboardShortcut.self, from: data)
        XCTAssertEqual(restored, original)
    }

    func test_equality_byKeyCodeAndModifiers() {
        let a = KeyboardShortcut(keyCode: 49, modifierFlags: .option)
        let b = KeyboardShortcut(keyCode: 49, modifierFlags: .option)
        let c = KeyboardShortcut(keyCode: 49, modifierFlags: .command)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
