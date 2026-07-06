import SwiftUI
import AppKit

/// Launcher 快捷键设置区。
///
/// 录制状态使用 NSEvent.addLocalMonitorForEvents 监听本地键盘事件,
/// 不安装任何全局监听器,也不要求辅助功能或输入监控权限。
struct ShortcutSettingsSection: View {
    @Environment(DependencyContainer.self) private var container

    @State private var launcherShortcut: KeyboardShortcut = .default
    @State private var clipboardPanelShortcut: KeyboardShortcut = .defaultClipboardPanel
    @State private var isRecording: Bool = false
    @State private var recordingAction: ShortcutAction?
    @State private var statusMessage: String = ""
    @State private var hasError: Bool = false
    @State private var monitor: Any?

    var body: some View {
        Section {
            shortcutRow(
                title: "聚焦搜索快捷键",
                subtitle: "打开 Launcher 悬浮面板",
                symbolName: "keyboard",
                shortcut: launcherShortcut,
                action: .launcher
            )

            shortcutRow(
                title: "剪切板面板快捷键",
                subtitle: "打开 Clipboard 悬浮面板",
                symbolName: "doc.on.clipboard",
                shortcut: clipboardPanelShortcut,
                action: .clipboardPanel
            )

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
            launcherShortcut = container.settings.readLauncherShortcut() ?? container.shortcutService.defaultShortcut(for: .launcher)
            clipboardPanelShortcut = container.settings.readClipboardPanelShortcut() ?? container.shortcutService.defaultShortcut(for: .clipboardPanel)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func shortcutRow(
        title: String,
        subtitle: String,
        symbolName: String,
        shortcut: KeyboardShortcut,
        action: ShortcutAction
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .foregroundStyle(OmnipoTheme.brandRed)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(shortcut.displayText)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            if isRecording && recordingAction == action {
                Button("取消") {
                    stopRecording()
                    statusMessage = "已取消录制"
                    hasError = false
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button("录制...") {
                    startRecording(action)
                }
                .disabled(isRecording)
            }

            Button("恢复默认") {
                Task { await restoreDefault(for: action) }
            }
            .disabled(isRecording)
        }
    }

    private func startRecording(_ action: ShortcutAction) {
        statusMessage = ""
        hasError = false
        recordingAction = action
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
        recordingAction = nil
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

        guard let action = recordingAction else { return }
        stopRecording()
        Task { await tryRegister(candidate, for: action) }
    }

    private func tryRegister(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async {
        let result = await container.shortcutService.register(shortcut, for: action)
        switch result {
        case .success(let registered):
            updateDisplayedShortcut(registered, for: action)
            writeShortcut(registered, for: action)
            statusMessage = "已保存,可使用 \(registered.displayText) 唤起\(actionDisplayName(action))。"
            hasError = false
        case .failure(let error):
            statusMessage = error.userDescription
            hasError = true
        }
    }

    private func restoreDefault(for action: ShortcutAction) async {
        let result = await container.shortcutService.restoreDefault(for: action)
        switch result {
        case .success(let shortcut):
            updateDisplayedShortcut(shortcut, for: action)
            writeShortcut(shortcut, for: action)
            statusMessage = "已恢复默认 \(shortcut.displayText)。"
            hasError = false
        case .failure(let error):
            statusMessage = error.userDescription
            hasError = true
        }
    }

    private func updateDisplayedShortcut(_ shortcut: KeyboardShortcut, for action: ShortcutAction) {
        switch action {
        case .launcher:
            launcherShortcut = shortcut
        case .clipboardPanel:
            clipboardPanelShortcut = shortcut
        }
    }

    private func writeShortcut(_ shortcut: KeyboardShortcut, for action: ShortcutAction) {
        switch action {
        case .launcher:
            container.settings.writeLauncherShortcut(shortcut)
        case .clipboardPanel:
            container.settings.writeClipboardPanelShortcut(shortcut)
        }
    }

    private func actionDisplayName(_ action: ShortcutAction) -> String {
        switch action {
        case .launcher:
            return "聚焦搜索"
        case .clipboardPanel:
            return "剪切板面板"
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
