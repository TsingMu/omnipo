import SwiftUI

struct SettingsView: View {
    @Environment(DependencyContainer.self) private var container

    @State private var launchDashboardAtStart: Bool = false
    @State private var reopenLastDestination: Bool = false
    @State private var preferredSidebarWidth: Double = 220

    var body: some View {
        Form {
            Section {
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
            } header: {
                Text("通用")
            } footer: {
                Text("Omnipo 仅在本地保存这些偏好,不上传任何数据。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Slider(value: $preferredSidebarWidth, in: 200...320) {
                    Text("侧边栏宽度")
                } minimumValueLabel: {
                    Text("窄")
                } maximumValueLabel: {
                    Text("宽")
                }
                .onChange(of: preferredSidebarWidth) { _, value in
                    let rounded = (value * 10).rounded() / 10
                    container.settings.write(rounded, forKey: .preferredSidebarWidth)
                }
            } header: {
                Text("界面")
            } footer: {
                Text("偏好仅在本地持久化,无关联账户或上传。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
        .task {
            launchDashboardAtStart = container.settings.readBool(forKey: .launchDashboardAtStart)
            reopenLastDestination = container.settings.readBool(forKey: .reopenLastDestination)
            preferredSidebarWidth = container.settings.readDouble(forKey: .preferredSidebarWidth)
        }
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
