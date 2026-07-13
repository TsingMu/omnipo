import SwiftUI

struct SettingsView: View {
    @Environment(DependencyContainer.self) private var container

    @State private var launchAtLoginController: LaunchAtLoginSettingsController?
    @State private var launchDashboardAtStart = false
    @State private var reopenLastDestination = false
    @State private var clipboardAutoPaste = true
    @State private var clipboardPanelPosition: ClipboardPanelPosition = .center
    @State private var clipboardMaxRecords = ClipboardSettingsDefaults.maxRecords
    @State private var clipboardRetentionDays = ClipboardSettingsDefaults.retentionDays
    @State private var clipboardMaxStorageMB = ClipboardSettingsDefaults.maxStorageMB
    @State private var excludedApplications: [String] = []
    @State private var excludedPatterns: [String] = []
    @State private var newPatternText = ""
    @State private var patternValidationMessage: String?
    @State private var pollingIntervalSeconds = ClipboardSettingsDefaults.pollingIntervalSeconds
    @State private var imageQuality = ClipboardSettingsDefaults.imageQuality
    @State private var showMenuBarIcon = ClipboardSettingsDefaults.showMenuBarIcon

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OmnipoTheme.redWash,
                    OmnipoTheme.deepBlack.opacity(0.035),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                header

                TabView {
                    generalTab
                        .tabItem { Label("通用", systemImage: "gearshape") }

                    storageTab
                        .tabItem { Label("存储", systemImage: "internaldrive") }

                    exclusionTab
                        .tabItem { Label("排除规则", systemImage: "hand.raised") }

                    advancedTab
                        .tabItem { Label("高级", systemImage: "wrench.and.screwdriver") }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 520, height: 520)
        .task {
            if launchAtLoginController == nil {
                let controller = LaunchAtLoginSettingsController(
                    service: container.launchAtLoginService,
                    settings: container.settings,
                    logger: container.logging
                )
                launchAtLoginController = controller
                controller.refresh()
            }
            loadSettings()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(OmnipoTheme.brandGradient)
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.title2.bold())
                Text("本地偏好、剪切板规则与快捷键")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var generalTab: some View {
        Form {
            Section {
                launchAtLoginSetting

                Toggle("启动时打开 Dashboard", isOn: $launchDashboardAtStart)
                    .onChange(of: launchDashboardAtStart) { _, value in
                        container.settings.write(value, forKey: .launchDashboardAtStart)
                        container.logging.log(.preferenceChanged(key: "launchDashboardAtStart"))
                    }

                Toggle("下次打开时恢复上次选择", isOn: $reopenLastDestination)
                    .onChange(of: reopenLastDestination) { _, value in
                        container.settings.write(value, forKey: .reopenLastDestination)
                        container.logging.log(.preferenceChanged(key: "reopenLastDestination"))
                    }

                Toggle("选中后自动粘贴", isOn: $clipboardAutoPaste)
                    .onChange(of: clipboardAutoPaste) { _, value in
                        container.settings.write(value, forKey: .clipboardAutoPaste)
                        container.logging.log(.preferenceChanged(key: "clipboardAutoPaste"))
                    }

                Picker("剪切板面板位置", selection: $clipboardPanelPosition) {
                    ForEach(ClipboardPanelPosition.allCases, id: \.self) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .onChange(of: clipboardPanelPosition) { _, value in
                    container.settings.writeClipboardPanelPosition(value)
                    container.logging.log(.preferenceChanged(key: "clipboardPanelPosition"))
                }

            } header: {
                Text("通用")
            } footer: {
                Text("Omnipo 仅在本地保存这些偏好,不上传任何数据。")
            }

            ShortcutSettingsSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var launchAtLoginSetting: some View {
        if let controller = launchAtLoginController {
            Toggle("开机时自动启动", isOn: Binding(
                get: { controller.isEnabled },
                set: { requestedValue in
                    Task { await controller.setEnabled(requestedValue) }
                }
            ))
            .disabled(controller.isUpdating)

            if let message = controller.message {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.orange)

                    Button("刷新开机启动状态") {
                        controller.refresh()
                    }
                    .controlSize(.small)
                }
            }
        } else {
            Toggle("开机时自动启动", isOn: .constant(false))
                .disabled(true)
        }
    }

    private var storageTab: some View {
        Form {
            Section("剪切板存储") {
                Picker("最大保留条数", selection: $clipboardMaxRecords) {
                    Text("500 条").tag(500.0)
                    Text("1000 条").tag(1_000.0)
                    Text("2000 条").tag(2_000.0)
                    Text("5000 条").tag(5_000.0)
                    Text("10000 条").tag(10_000.0)
                }
                .onChange(of: clipboardMaxRecords) { _, value in
                    container.settings.writeClipboardMaxRecords(value)
                    clipboardMaxRecords = container.settings.readClipboardMaxRecords()
                    container.logging.log(.preferenceChanged(key: "clipboardMaxRecords"))
                }

                Picker("保留天数", selection: $clipboardRetentionDays) {
                    Text("7 天").tag(7.0)
                    Text("14 天").tag(14.0)
                    Text("30 天").tag(30.0)
                    Text("60 天").tag(60.0)
                    Text("90 天").tag(90.0)
                    Text("永久").tag(365.0)
                }
                .onChange(of: clipboardRetentionDays) { _, value in
                    container.settings.writeClipboardRetentionDays(value)
                    clipboardRetentionDays = container.settings.readClipboardRetentionDays()
                    container.logging.log(.preferenceChanged(key: "clipboardRetentionDays"))
                }

                Picker("最大存储空间", selection: $clipboardMaxStorageMB) {
                    Text("100 MB").tag(100.0)
                    Text("250 MB").tag(250.0)
                    Text("500 MB").tag(500.0)
                    Text("1 GB").tag(1_000.0)
                    Text("2 GB").tag(2_000.0)
                }
                .onChange(of: clipboardMaxStorageMB) { _, value in
                    container.settings.writeClipboardMaxStorageMB(value)
                    clipboardMaxStorageMB = container.settings.readClipboardMaxStorageMB()
                    container.logging.log(.preferenceChanged(key: "clipboardMaxStorageMB"))
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var exclusionTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("排除的应用")
                .font(.headline)
            Text("这些应用复制的内容不会被记录。")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(excludedApplications, id: \.self) { bundleID in
                    Text(bundleID)
                        .lineLimit(1)
                }
                .onDelete { indices in
                    excludedApplications.remove(atOffsets: indices)
                    saveExcludedApplications()
                }
            }
            .frame(minHeight: 96)

            Button {
                addFrontmostApplicationToExclusions()
            } label: {
                Label("添加当前应用", systemImage: "plus")
            }

            Divider()

            Text("排除的内容规则")
                .font(.headline)
            Text("匹配这些正则表达式的文本内容不会被记录。")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(excludedPatterns, id: \.self) { pattern in
                    Text(pattern)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                }
                .onDelete { indices in
                    excludedPatterns.remove(atOffsets: indices)
                    saveExcludedPatterns()
                }
            }
            .frame(minHeight: 82)

            HStack {
                TextField("输入正则表达式", text: $newPatternText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Button("添加") {
                    addExcludedPattern()
                }
                .disabled(newPatternText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let patternValidationMessage {
                Text(patternValidationMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
    }

    private var advancedTab: some View {
        Form {
            Section("高级") {
                Toggle("显示菜单栏图标", isOn: $showMenuBarIcon)
                    .onChange(of: showMenuBarIcon) { _, value in
                        container.settings.write(value, forKey: .showMenuBarIcon)
                        NotificationCenter.default.post(name: .menuBarVisibilitySettingDidChange, object: nil)
                        container.logging.log(.preferenceChanged(key: "showMenuBarIcon"))
                    }

                VStack(alignment: .leading) {
                    Text("剪切板轮询间隔: \(String(format: "%.1f", pollingIntervalSeconds)) 秒")
                    Slider(value: $pollingIntervalSeconds, in: 0.1...2.0, step: 0.1) {
                        Text("剪切板轮询间隔")
                    }
                    .onChange(of: pollingIntervalSeconds) { _, value in
                        container.settings.writeClipboardPollingIntervalSeconds(value)
                        pollingIntervalSeconds = container.settings.readClipboardPollingIntervalSeconds()
                        container.logging.log(.preferenceChanged(key: "clipboardPollingIntervalSeconds"))
                    }
                }

                VStack(alignment: .leading) {
                    Text("图片压缩质量: \(Int(imageQuality * 100))%")
                    Slider(value: $imageQuality, in: 0.1...1.0, step: 0.1) {
                        Text("图片压缩质量")
                    }
                    .onChange(of: imageQuality) { _, value in
                        container.settings.writeClipboardImageQuality(value)
                        imageQuality = container.settings.readClipboardImageQuality()
                        container.logging.log(.preferenceChanged(key: "clipboardImageQuality"))
                    }
                }
            }

            Section {
                Button("恢复 Clippy 风格默认设置") {
                    container.settings.resetClippyStyleSettingsToDefaults()
                    loadSettings()
                    NotificationCenter.default.post(name: .menuBarVisibilitySettingDidChange, object: nil)
                    container.logging.log(.preferenceChanged(key: "resetClippyStyleSettings"))
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func loadSettings() {
        launchDashboardAtStart = container.settings.readBool(forKey: .launchDashboardAtStart)
        reopenLastDestination = container.settings.readBool(forKey: .reopenLastDestination)
        clipboardAutoPaste = container.settings.readBool(forKey: .clipboardAutoPaste)
        clipboardPanelPosition = container.settings.readClipboardPanelPosition()
        clipboardMaxRecords = container.settings.readClipboardMaxRecords()
        clipboardRetentionDays = container.settings.readClipboardRetentionDays()
        clipboardMaxStorageMB = container.settings.readClipboardMaxStorageMB()
        excludedApplications = container.settings.readClipboardExcludedApplications()
        excludedPatterns = container.settings.readClipboardExcludedPatterns()
        pollingIntervalSeconds = container.settings.readClipboardPollingIntervalSeconds()
        imageQuality = container.settings.readClipboardImageQuality()
        showMenuBarIcon = container.settings.readBool(forKey: .showMenuBarIcon)
    }

    private func addFrontmostApplicationToExclusions() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              !excludedApplications.contains(bundleID) else {
            return
        }
        excludedApplications.append(bundleID)
        saveExcludedApplications()
    }

    private func saveExcludedApplications() {
        container.settings.writeClipboardExcludedApplications(excludedApplications)
        container.logging.log(.preferenceChanged(key: "clipboardExcludedApplications"))
    }

    private func addExcludedPattern() {
        let trimmed = newPatternText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard (try? NSRegularExpression(pattern: trimmed)) != nil else {
            patternValidationMessage = "正则表达式无效。"
            return
        }
        guard !excludedPatterns.contains(trimmed) else {
            newPatternText = ""
            patternValidationMessage = nil
            return
        }
        excludedPatterns.append(trimmed)
        newPatternText = ""
        patternValidationMessage = nil
        saveExcludedPatterns()
    }

    private func saveExcludedPatterns() {
        container.settings.writeClipboardExcludedPatterns(excludedPatterns)
        container.logging.log(.preferenceChanged(key: "clipboardExcludedPatterns"))
    }
}

private extension LogEvent {
    static func preferenceChanged(key: String) -> LogEvent {
        LogEvent(
            level: .info,
            category: .settings,
            message: "settings.updated",
            stableCode: "I_SETTINGS_UPDATED",
            sanitizedContext: ["key": key]
        )
    }
}

#Preview {
    SettingsView()
        .environment(DependencyContainer.production())
}
