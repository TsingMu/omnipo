import AppKit
import Foundation
import SwiftUI

@MainActor
public final class ClipboardPanelController {
    private let clipboardService: any ClipboardService
    private let settings: any SettingsService
    private var panel: NSPanel?
    private var lastPanelOrigin: NSPoint?
    private var pasteTargetProcessIdentifier: pid_t?
    nonisolated(unsafe) private var resignObserver: NSObjectProtocol?

    public init(clipboardService: any ClipboardService, settings: any SettingsService) {
        self.clipboardService = clipboardService
        self.settings = settings
    }

    public func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        capturePasteTargetProcessIdentifier()
        let resolved = ensurePanel()
        position(resolved)
        resolved.orderFrontRegardless()
        resolved.makeKey()
    }

    public func hide() {
        if let panel {
            lastPanelOrigin = panel.frame.origin
        }
        panel?.orderOut(nil)
    }

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NonActivatingClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Omnipo Clipboard"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        panel.contentView = NSHostingView(
            rootView: ClipboardPanelView(
                clipboardService: clipboardService,
                settings: settings,
                pasteTargetProcessIdentifier: { [weak self] in
                    self?.pasteTargetProcessIdentifier
                },
                onHide: { [weak self] in
                    self?.hide()
                }
            )
        )

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

    private func position(_ panel: NSPanel) {
        switch settings.readClipboardPanelPosition() {
        case .center:
            positionAtCurrentScreen(panel, relativeToMouse: false)
        case .followMouse:
            positionAtCurrentScreen(panel, relativeToMouse: true)
        case .lastPosition:
            if let lastPanelOrigin {
                panel.setFrameOrigin(lastPanelOrigin)
            } else {
                positionAtCurrentScreen(panel, relativeToMouse: false)
            }
        }
    }

    private func capturePasteTargetProcessIdentifier() {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if let processIdentifier = frontmostApplication?.processIdentifier,
           processIdentifier != currentProcessIdentifier {
            pasteTargetProcessIdentifier = processIdentifier
        } else {
            pasteTargetProcessIdentifier = nil
        }
    }

    private func positionAtCurrentScreen(_ panel: NSPanel, relativeToMouse: Bool) {
        let screen: NSScreen
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            screen = mouseScreen
        } else if let mainScreen = NSScreen.main {
            screen = mainScreen
        } else if let first = NSScreen.screens.first {
            screen = first
        } else {
            panel.center()
            return
        }

        let visible = screen.visibleFrame
        let panelSize = panel.frame.size
        let target: NSPoint
        if relativeToMouse {
            target = NSPoint(
                x: mouseLocation.x - panelSize.width / 2,
                y: mouseLocation.y - panelSize.height - 12
            )
        } else {
            target = NSPoint(
                x: visible.midX - panelSize.width / 2,
                y: visible.midY - panelSize.height / 2
            )
        }
        panel.setFrameOrigin(clampedOrigin(target, panelSize: panelSize, visibleFrame: visible))
    }

    private func clampedOrigin(_ origin: NSPoint, panelSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8),
            y: min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - panelSize.height - 8)
        )
    }

    deinit {
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

private final class NonActivatingClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
