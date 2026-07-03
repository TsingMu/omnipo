import Foundation
import AppKit
import SwiftUI

/// Launcher 浮动面板的协调协议。
///
/// `LauncherPanelController` 只负责窗口生命周期与第一响应者,
/// 业务执行(导航、启动、打开文件)由实现此协议的协调层处理。
@MainActor
public protocol LauncherPanelDelegate: AnyObject {
    func launcherPanelDidRequestHide()
    func launcherPanelDidRequestExecute(_ result: SearchResult)
    func launcherPanelDidRequestFileAction(_ action: FileLauncher.Action, for result: SearchResult)
}

/// 拥有唯一 `NSPanel` 的窄 AppKit 控制器。
///
/// 不保存查询、不执行业务,只负责显示、隐藏、当前屏幕定位与第一响应者。
/// SwiftUI 内容由 `LauncherPanelView` 提供,所有状态来自 `LauncherStore`。
@MainActor
public final class LauncherPanelController {
    private weak var delegate: LauncherPanelDelegate?
    private let store: LauncherStore
    private let applicationResourceCache: ApplicationResourceCache
    private var panel: NSPanel?
    nonisolated(unsafe) private var resignObserver: NSObjectProtocol?

    public init(
        store: LauncherStore,
        applicationResourceCache: ApplicationResourceCache
    ) {
        self.store = store
        self.applicationResourceCache = applicationResourceCache
    }

    public func attach(delegate: LauncherPanelDelegate) {
        self.delegate = delegate
    }

    public func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        let resolved = ensurePanel()
        store.cancelAll()
        // 触发空查询,让应用索引立即返回默认应用列表。
        store.updateQuery("")
        positionAtCurrentScreen(resolved)
        resolved.orderFrontRegardless()
        focusSearchField(in: resolved)
    }

    public func hide() {
        panel?.orderOut(nil)
        store.cancelAll()
    }

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    var resourceCache: ApplicationResourceCache {
        applicationResourceCache
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NonActivatingLauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Omnipo 聚焦搜索"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(
            rootView: LauncherPanelView(
                store: store,
                applicationResourceCache: applicationResourceCache,
                onExecute: { [weak self] result in
                    self?.delegate?.launcherPanelDidRequestExecute(result)
                },
                onHide: { [weak self] in
                    self?.delegate?.launcherPanelDidRequestHide()
                },
                onFileAction: { [weak self] action, result in
                    self?.delegate?.launcherPanelDidRequestFileAction(action, for: result)
                }
            )
        )
        panel.contentView = hosting

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }

        self.panel = panel
        return panel
    }

    private func positionAtCurrentScreen(_ panel: NSPanel) {
        let screen: NSScreen
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) {
            screen = mouseScreen
        } else if let mainScreen = NSScreen.main {
            screen = mainScreen
        } else if let first = NSScreen.screens.first {
            screen = first
        } else {
            panel.center()
            return
        }

        let visible = screen.visibleAreaFrame
        let panelSize = panel.frame.size
        let x = visible.midX - panelSize.width / 2
        let y = visible.maxY - panelSize.height - visible.height * 0.2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func focusSearchField(in panel: NSPanel) {
        panel.makeKey()
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible else { return }
            panel.makeKey()
            if let field = panel.contentView?.firstSubview(ofType: LauncherSearchTextField.self) {
                panel.makeFirstResponder(field)
            }
        }
    }

    deinit {
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

private final class NonActivatingLauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private extension NSScreen {
    /// 屏幕可工作区域(去掉 menu bar 与 Dock)。`visibleFrame` 已是此区域。
    var visibleAreaFrame: NSRect {
        visibleFrame
    }
}

private extension NSView {
    func firstSubview<T: NSView>(ofType type: T.Type) -> T? {
        if let view = self as? T {
            return view
        }
        for subview in subviews {
            if let match = subview.firstSubview(ofType: type) {
                return match
            }
        }
        return nil
    }
}
