import SwiftUI
import AppKit

/// Launcher 快捷键设置区。
///
/// 录制状态使用 NSEvent.addLocalMonitorForEvents 监听本地键盘事件,
/// 不安装任何全局监听器,也不要求辅助功能或输入监控权限。
struct ShortcutSettingsSection: View {
    @Environment(DependencyContainer.self) private var container

    @State private var currentShortcut: KeyboardShortcut = .default
    @State private var isRecording: Bool = false
    @State private var statusMessage: String = ""
    @State private var hasError: Bool = false
    @State private var monitor: Any?

    var body: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launcher 快捷键")
                        .font(.headline)
                    Text(currentShortcut.displayText)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }

                Spacer()

                if isRecording {
                    Button("取消") {
                        stopRecording()
                    }
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button("录制...") {
                        startRecording()
                    }
                }

                Button("恢复默认") {
                    Task { await restoreDefault() }
                }
                .disabled(isRecording)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(hasError ? .red : .secondary)
            }
        } header: {
            Text("全局快捷键")
        } footer: {
            Text("Omnipo 仅本地保存快捷键,不上传任何数据。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            currentShortcut = persistedOrFallback()
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func persistedOrFallback() -> KeyboardShortcut {
        if let stored = container.settings.readLauncherShortcut() {
            return stored
        }
        return .default
    }

    private func startRecording() {
        statusMessage = ""
        hasError = false
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleKeyEvent(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53 {
            stopRecording()
            statusMessage = "已取消录制"
            return
        }
        if modifiers.isEmpty {
            statusMessage = "请至少按住一个修饰键(⌘/⌥/⌃/⇧)。"
            hasError = true
            return
        }
        if isModifierKeyCode(event.keyCode) {
            return
        }

        let carbonModifiers = KeyboardShortcut.ModifierFlags(
            rawValue: carbonMask(from: modifiers)
        )
        let candidate = KeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            modifierFlags: carbonModifiers
        )
        guard candidate.isValid else {
            statusMessage = "无效组合,请使用至少一个修饰键加一个普通键。"
            hasError = true
            return
        }

        stopRecording()
        Task { await tryRegister(candidate) }
    }

    private func tryRegister(_ shortcut: KeyboardShortcut) async {
        let result = await container.shortcutService.register(shortcut)
        switch result {
        case .success(let registered):
            currentShortcut = registered
            container.settings.writeLauncherShortcut(registered)
            statusMessage = "已保存,可使用 \(registered.displayText) 唤起。"
            hasError = false
        case .failure(let error):
            statusMessage = error.userDescription
            hasError = true
        }
    }

    private func restoreDefault() async {
        let result = await container.shortcutService.restoreDefault()
        switch result {
        case .success:
            currentShortcut = .default
            container.settings.writeLauncherShortcut(.default)
            statusMessage = "已恢复默认 Option + Space。"
            hasError = false
        case .failure(let error):
            statusMessage = error.userDescription
            hasError = true
        }
    }

    private func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55: return true  // right-cmd, left-cmd
        case 58, 61: return true  // right-option, left-option
        case 56, 60: return true  // right-shift, left-shift
        case 59, 62: return true  // right-control, left-control
        default: return false
        }
    }

    private func carbonMask(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= 1 << 8 }
        if flags.contains(.shift) { mask |= 1 << 9 }
        if flags.contains(.option) { mask |= 1 << 11 }
        if flags.contains(.control) { mask |= 1 << 12 }
        return mask
    }
}
