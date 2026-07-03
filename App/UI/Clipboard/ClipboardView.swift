import SwiftUI

struct ClipboardView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var hasAcknowledgedNotice = false
    @State private var isEnabled = false
    @State private var errorMessage: String?

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
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if hasAcknowledgedNotice {
                        enabledControls
                    } else {
                        firstUseNotice
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(.top, 4)
                    }

                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            await refreshState()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(OmnipoTheme.brandGradient)
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Clipboard")
                    .font(.largeTitle.bold())
                Text("记录最近复制内容,稍后可搜索、收藏或再次粘贴。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var firstUseNotice: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("首次启用前请确认", systemImage: "lock.shield")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Label("剪切板内容只保存在这台 Mac 的本地数据库和本地文件目录中。", systemImage: "internaldrive")
                Label("复制的密码、验证码、私钥、证件号等敏感内容也可能被记录。", systemImage: "exclamationmark.triangle")
                Label("确认前不会启动监听,也不会持久化任何剪切板内容。", systemImage: "pause.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Button {
                Task {
                    await acknowledgeAndEnable()
                }
            } label: {
                Label("确认并启用", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var enabledControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isEnabled ? "record.circle" : "pause.circle")
                    .font(.title2)
                    .foregroundStyle(isEnabled ? OmnipoTheme.brandRed : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isEnabled ? "正在记录剪切板" : "剪切板记录已关闭")
                        .font(.headline)
                    Text(isEnabled ? "新复制的受支持内容会保存在本地。" : "不会监听或保存新内容,已有记录保留供后续管理。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("记录", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        Task {
                            await setEnabled(newValue)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("记录剪切板")
            }

            if !isEnabled {
                Button {
                    Task {
                        await setEnabled(true)
                    }
                } label: {
                    Label("重新启用记录", systemImage: "play.circle")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func acknowledgeAndEnable() async {
        errorMessage = nil
        switch await container.clipboardService.acknowledgeLocalStorageNotice() {
        case .success:
            await refreshState()
        case .failure(let error):
            errorMessage = error.userDescription
        }
    }

    private func setEnabled(_ newValue: Bool) async {
        errorMessage = nil
        switch await container.clipboardService.setEnabled(newValue) {
        case .success:
            await refreshState()
        case .failure(let error):
            errorMessage = error.userDescription
            await refreshState()
        }
    }

    private func refreshState() async {
        hasAcknowledgedNotice = await container.clipboardService.hasAcknowledgedLocalStorageNotice
        isEnabled = await container.clipboardService.isEnabled
    }
}

#Preview {
    ClipboardView()
        .environment(DependencyContainer.production())
        .frame(width: 720, height: 540)
}
