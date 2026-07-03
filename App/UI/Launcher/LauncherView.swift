import SwiftUI

struct LauncherView: View {
    @Environment(DependencyContainer.self) private var container

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

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(OmnipoTheme.brandGradient)
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 52, height: 52)

                            Text("聚焦搜索")
                                .font(.largeTitle.bold())
                        }

                        Text("默认聚焦应用；输入 find 加空格后搜索文件，也可随时使用全局快捷键 Option + Space 打开独立面板。")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Label("本地搜索", systemImage: "checkmark.shield")
                        Label("支持键盘操作", systemImage: "keyboard")
                        Label("Option + Space", systemImage: "command")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    LauncherWorkbenchCard()

                    HStack {
                        Label("需要悬浮面板时，可继续使用全局快捷键或手动打开。", systemImage: "rectangle.stack")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            container.launcherCoordinator.panelController.show()
                        } label: {
                            Label("打开悬浮面板", systemImage: "rectangle.stack.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    LauncherView()
        .environment(DependencyContainer.production())
        .frame(width: 840, height: 620)
}
