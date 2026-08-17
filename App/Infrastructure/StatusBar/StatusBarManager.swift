import AppKit

@MainActor
public final class StatusBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private let container: DependencyContainer
    nonisolated(unsafe) private var visibilityObserver: NSObjectProtocol?

    private var networkSpeedView: MenuBarNetworkSpeedView?
    private var samplingController: MenuBarNetworkSamplingController?

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
            button.toolTip = "Omnipo"
            // 状态项是唯一可操作焦点:辅助功能信息设置在按钮本体,
            // 数值每秒更新但不发送主动播报
            button.setAccessibilityLabel("Omnipo 网络速率")
            button.setAccessibilityValue(MenuBarNetworkRateFormatter.accessibilityText(from: .warmingUp))
            let view = MenuBarNetworkSpeedView(icon: statusBarIcon())
            view.frame = button.bounds
            view.autoresizingMask = [.width, .height]
            button.addSubview(view)
            networkSpeedView = view
            // 图标与速率由展示视图绘制;长度取视图稳定宽度
            item.length = MenuBarNetworkSpeedView.preferredWidth
        } else {
            item.length = NSStatusItem.squareLength
        }
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
        if container.settings.readBool(forKey: .showMenuBarIcon) {
            // 显示同步生效:最新设置始终获胜
            statusItem?.isVisible = true
            makeSamplingController().show()
        } else {
            makeSamplingController().hide()
        }
    }

    private func makeSamplingController() -> MenuBarNetworkSamplingController {
        if let samplingController {
            return samplingController
        }
        let controller = MenuBarNetworkSamplingController(
            makeMonitor: { [container] in
                MenuBarNetworkRateMonitor(sampler: NetworkSampler(logger: container.logging))
            },
            onAvailability: { [weak self] availability in
                guard let self else { return }
                self.networkSpeedView?.update(with: availability)
                self.statusItem?.button?.setAccessibilityValue(
                    MenuBarNetworkRateFormatter.accessibilityText(from: availability)
                )
            },
            onApplyHidden: { [weak self] in
                guard let self else { return }
                self.networkSpeedView?.update(with: .warmingUp)
                self.statusItem?.button?.setAccessibilityValue(
                    MenuBarNetworkRateFormatter.accessibilityText(from: .warmingUp)
                )
                self.statusItem?.isVisible = false
            }
        )
        samplingController = controller
        return controller
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

/// 菜单栏网络采样的可见性编排器,不依赖 AppKit,便于并发行为单元测试。
///
/// 每次可见性转换都递增单调 `generation` 并绑定到后台任务:
/// - 显示任务在提交 `start` 前核对最新代次与取消状态,已取消或过期的任务不得创建采样会话;
/// - 隐藏任务在 `stop` 前后都复核代次,`await` 期间被更新的显示取代时不得回写隐藏;
/// - monitor 侧以请求代次门控,迟到的过期 start 被拒绝、过期 stop 不得停止新会话,
///   与 actor 队列的实际到达顺序无关。
/// 最新一次设置始终获胜:隐藏状态下不存在仍在运行的采样任务。
@MainActor
final class MenuBarNetworkSamplingController {

    private let makeMonitor: () -> MenuBarNetworkRateMonitor
    private let onAvailability: (MenuBarNetworkRateAvailability) -> Void
    private let onApplyHidden: () -> Void

    private var monitor: MenuBarNetworkRateMonitor?
    private var subscriptionTask: Task<Void, Never>?
    private var generation = 0

    init(
        makeMonitor: @escaping () -> MenuBarNetworkRateMonitor,
        onAvailability: @escaping (MenuBarNetworkRateAvailability) -> Void,
        onApplyHidden: @escaping () -> Void
    ) {
        self.makeMonitor = makeMonitor
        self.onAvailability = onAvailability
        self.onApplyHidden = onApplyHidden
    }

    deinit {
        subscriptionTask?.cancel()
    }

    private func isCurrentGeneration(_ generation: Int) -> Bool {
        generation == self.generation
    }

    /// 显示并启动采样;重复显示不重启会话,仅替换订阅任务。
    func show() {
        generation += 1
        let current = generation

        let hadSubscription = subscriptionTask != nil
        subscriptionTask?.cancel()
        subscriptionTask = nil

        let monitor = self.monitor ?? makeMonitor()
        self.monitor = monitor

        if !hadSubscription {
            onAvailability(.warmingUp)
        }

        subscriptionTask = Task { [weak self, monitor, current] in
            // 已取消或已被更新代次取代的任务不得创建采样会话;
            // self 仅瞬时强引用,避免任务长期持有控制器形成引用环
            guard !Task.isCancelled, self?.isCurrentGeneration(current) == true else { return }
            let stream = await monitor.start(requestGeneration: current)
            for await availability in stream {
                // 元素可能在已提交给本任务后才发生取消或代次更新:
                // 写入前复核,旧会话速率不得覆盖新会话的预热 UI 与按钮辅助功能值
                guard let self, !Task.isCancelled, self.isCurrentGeneration(current) else {
                    return
                }
                self.onAvailability(availability)
            }
        }
    }

    /// 隐藏:先取消订阅并停止采样,`stop` 完成且代次仍最新时才回写隐藏。
    func hide() {
        generation += 1
        let current = generation
        let monitor = self.monitor

        Task { [weak self, monitor, current] in
            guard let self, self.generation == current else { return }
            self.subscriptionTask?.cancel()
            self.subscriptionTask = nil
            await monitor?.stop(requestGeneration: current)
            // await 期间 MainActor 可重入:过期隐藏不得覆盖更新的显示
            guard self.generation == current else { return }
            self.onApplyHidden()
        }
    }
}
