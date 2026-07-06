import AppKit

@MainActor
public final class StatusBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private let container: DependencyContainer
    nonisolated(unsafe) private var visibilityObserver: NSObjectProtocol?

    public init(container: DependencyContainer) {
        self.container = container
    }

    deinit {
        if let visibilityObserver {
            NotificationCenter.default.removeObserver(visibilityObserver)
        }
    }

    public func setup() {
        createStatusItemIfNeeded()
        applyVisibilitySetting()
        refreshMenu()
        observeVisibilitySetting()
    }

    private func createStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: 0)
        item.behavior = []
        if let button = item.button {
            button.image = statusBarIcon()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Omnipo"
            if button.image == nil {
                button.title = "O"
            }
        }
        item.length = NSStatusItem.squareLength
        statusItem = item
    }

    private func statusBarIcon() -> NSImage? {
        let image = NSImage(named: "StatusBarIcon")
            ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Omnipo")

        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        image?.accessibilityDescription = "Omnipo"
        return image
    }

    private func refreshMenu() {
        statusItem?.menu = buildMenu()
    }

    private func applyVisibilitySetting() {
        statusItem?.isVisible = container.settings.readBool(forKey: .showMenuBarIcon)
    }

    private func observeVisibilitySetting() {
        guard visibilityObserver == nil else { return }
        visibilityObserver = NotificationCenter.default.addObserver(
            forName: .menuBarVisibilitySettingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyVisibilitySetting()
            }
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Omnipo", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let openMainItem = NSMenuItem(
            title: "打开 Omnipo",
            action: #selector(openMainWindow),
            keyEquivalent: ""
        )
        openMainItem.target = self
        menu.addItem(openMainItem)

        let launcherItem = NSMenuItem(
            title: "打开聚焦搜索",
            action: #selector(openLauncher),
            keyEquivalent: ""
        )
        launcherItem.target = self
        launcherItem.keyEquivalentModifierMask = [.option]
        launcherItem.keyEquivalent = " "
        menu.addItem(launcherItem)

        menu.addItem(.separator())

        for destination in statusMenuDestinations {
            let item = NSMenuItem(
                title: destination.title,
                action: #selector(openDestination(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = destination.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "设置...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 Omnipo",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    private var statusMenuDestinations: [AppDestination] {
        [
            .dashboard,
            .launcher,
            .cleaner,
            .uninstaller,
            .permissionAudit,
            .wechatManager,
            .systemMonitor
        ]
    }

    @objc private func openMainWindow() {
        container.mainNavigator.activateMainWindow()
    }

    @objc private func openLauncher() {
        container.launcherCoordinator.panelController.toggle()
    }

    @objc private func openDestination(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let destination = AppDestination(rawValue: rawValue) else {
            return
        }

        container.mainNavigator.navigate(to: destination)
        container.mainNavigator.activateMainWindow()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
