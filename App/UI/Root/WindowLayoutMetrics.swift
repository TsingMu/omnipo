import AppKit
import SwiftUI

enum MainWindowLayout {
    private static let sidebarContentClearance: CGFloat = 16
    private static let detailContentClearance: CGFloat = 12

    static func titlebarInset(safeAreaTop: CGFloat, windowTitlebarHeight: CGFloat) -> CGFloat {
        max(0, safeAreaTop, windowTitlebarHeight)
    }

    static func sidebarTopInset(safeAreaTop: CGFloat, windowTitlebarHeight: CGFloat) -> CGFloat {
        let titlebarInset = titlebarInset(
            safeAreaTop: safeAreaTop,
            windowTitlebarHeight: windowTitlebarHeight
        )
        return titlebarInset > 0 ? titlebarInset + sidebarContentClearance : 0
    }

    static func detailTopInset(safeAreaTop: CGFloat, windowTitlebarHeight: CGFloat) -> CGFloat {
        let titlebarInset = titlebarInset(
            safeAreaTop: safeAreaTop,
            windowTitlebarHeight: windowTitlebarHeight
        )
        return titlebarInset > 0 ? titlebarInset + detailContentClearance : 0
    }
}

struct WindowTitlebarHeightReader: NSViewRepresentable {
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WindowTitlebarProbeView {
        let view = WindowTitlebarProbeView()
        view.onHeightChange = updateHeight
        return view
    }

    func updateNSView(_ nsView: WindowTitlebarProbeView, context: Context) {
        nsView.onHeightChange = updateHeight
        nsView.publishCurrentHeight()
    }

    private func updateHeight(_ newHeight: CGFloat) {
        guard height != newHeight else { return }
        height = newHeight
    }
}

final class WindowTitlebarProbeView: NSView {
    var onHeightChange: ((CGFloat) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowResize()
        publishCurrentHeight()
    }

    override func layout() {
        super.layout()
        publishCurrentHeight()
    }

    func publishCurrentHeight() {
        guard let window else { return }
        let titlebarHeight = max(0, window.frame.height - window.contentLayoutRect.height)
        onHeightChange?(titlebarHeight)
    }

    private func observeWindowResize() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    @objc private func windowDidResize() {
        publishCurrentHeight()
    }
}
