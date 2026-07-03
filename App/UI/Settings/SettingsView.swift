import SwiftUI

struct SettingsView: View {
    @Environment(DependencyContainer.self) private var container

    @State private var launchDashboardAtStart: Bool = false
    @State private var reopenLastDestination: Bool = false

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
                        Text("本地偏好与快捷键")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

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

                    ShortcutSettingsSection()
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 460)
        .task {
            launchDashboardAtStart = container.settings.readBool(forKey: .launchDashboardAtStart)
            reopenLastDestination = container.settings.readBool(forKey: .reopenLastDestination)
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
