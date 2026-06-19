import AppKit
import SwiftUI

/// Launcher 搜索输入的最小 AppKit 边界。
///
/// SwiftUI/LauncherStore 仍拥有值状态；此桥接只读取 Field Editor 的 marked text，
/// 并在没有组合文本时把局部键盘命令转发给 Launcher。
struct LauncherSearchField: NSViewRepresentable {
    let inputState: LauncherInputState
    let onInputStateChange: (LauncherInputState) -> Void
    let onMoveSelection: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onInputStateChange: onInputStateChange,
            onMoveSelection: onMoveSelection,
            onSubmit: onSubmit,
            onCancel: onCancel
        )
    }

    func makeNSView(context: Context) -> LauncherSearchTextField {
        let field = LauncherSearchTextField()
        field.delegate = context.coordinator
        field.placeholderString = "搜索应用、文件、功能…"
        field.font = .systemFont(ofSize: 18)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel("Launcher 搜索")
        return field
    }

    func updateNSView(_ field: LauncherSearchTextField, context: Context) {
        context.coordinator.update(
            onInputStateChange: onInputStateChange,
            onMoveSelection: onMoveSelection,
            onSubmit: onSubmit,
            onCancel: onCancel
        )

        // 组合期间 Field Editor 是权威来源，不能用 SwiftUI 回写打断候选。
        guard !inputState.isComposing else { return }
        if field.stringValue != inputState.displayedText {
            field.stringValue = inputState.displayedText
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var onInputStateChange: (LauncherInputState) -> Void
        private var onMoveSelection: (Int) -> Void
        private var onSubmit: () -> Void
        private var onCancel: () -> Void

        init(
            onInputStateChange: @escaping (LauncherInputState) -> Void,
            onMoveSelection: @escaping (Int) -> Void,
            onSubmit: @escaping () -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onInputStateChange = onInputStateChange
            self.onMoveSelection = onMoveSelection
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        func update(
            onInputStateChange: @escaping (LauncherInputState) -> Void,
            onMoveSelection: @escaping (Int) -> Void,
            onSubmit: @escaping () -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onInputStateChange = onInputStateChange
            self.onMoveSelection = onMoveSelection
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ notification: Notification) {
            publishInputState(from: notification.object as? NSTextField)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            publishInputState(from: notification.object as? NSTextField)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard let command = LauncherSearchKeyCommand(commandSelector) else {
                return false
            }

            // marked text 存在时不消费按键：Return/方向键/Escape 继续由输入法处理。
            guard !textView.hasMarkedText() else {
                return false
            }

            switch command {
            case .moveUp:
                onMoveSelection(-1)
            case .moveDown:
                onMoveSelection(1)
            case .submit:
                onSubmit()
            case .cancel:
                onCancel()
            }
            return true
        }

        private func publishInputState(from field: NSTextField?) {
            guard let field else { return }
            let editor = field.currentEditor() as? NSTextView
            let displayedText = editor?.string ?? field.stringValue
            let isComposing = editor?.hasMarkedText() ?? false
            onInputStateChange(LauncherInputState(
                displayedText: displayedText,
                effectiveQuery: displayedText,
                isComposing: isComposing
            ))
        }
    }
}

@MainActor
final class LauncherSearchTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }
}

enum LauncherSearchKeyCommand: Equatable {
    case moveUp
    case moveDown
    case submit
    case cancel

    init?(_ selector: Selector) {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            self = .moveUp
        case #selector(NSResponder.moveDown(_:)):
            self = .moveDown
        case #selector(NSResponder.insertNewline(_:)):
            self = .submit
        case #selector(NSResponder.cancelOperation(_:)):
            self = .cancel
        default:
            return nil
        }
    }
}
