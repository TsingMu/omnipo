import AppKit
import Observation
import SwiftUI

struct UninstallerView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var store: UninstallerStore?

    var body: some View {
        Group {
            if let store {
                UninstallerContent(store: store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if store == nil {
                store = UninstallerStore(service: container.uninstallerService)
            }
            await store?.loadIfNeeded()
        }
    }
}

@MainActor
@Observable
private final class UninstallerStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(AppError)
    }

    enum ExecutionState: Equatable {
        case idle
        case buildingPlan
        case ready
        case executing
        case completed(UninstallExecutionResult)
        case failed(AppError)
    }

    var query = UninstallerQuery()
    var applications: [InstalledApplication] = []
    var selectedApplicationID: InstalledApplication.ID?
    var mode: UninstallMode = .removeApplicationOnly
    var plan: AppUninstallPlan?
    var loadState: LoadState = .idle
    var executionState: ExecutionState = .idle
    var lastExecutionResult: UninstallExecutionResult?
    var executionNotice: UninstallerExecutionNotice?
    var isConfirmationPresented = false

    private let service: any UninstallerService

    init(service: any UninstallerService) {
        self.service = service
    }

    var selectedApplication: InstalledApplication? {
        applications.first { $0.id == selectedApplicationID }
    }

    var isBusy: Bool {
        loadState == .loading || executionState == .buildingPlan || executionState == .executing
    }

    func loadIfNeeded() async {
        guard loadState == .idle else { return }
        await refresh()
    }

    func refresh() async {
        loadState = .loading
        clearExecutionFeedback()
        let result = await service.installedApplications(matching: query)
        switch result {
        case .success(let applications):
            self.applications = applications
            if let selectedApplicationID,
               applications.contains(where: { $0.id == selectedApplicationID }) == false {
                self.selectedApplicationID = applications.first?.id
            } else if selectedApplicationID == nil {
                selectedApplicationID = applications.first?.id
            }
            loadState = .loaded
            await rebuildPlan()
        case .failure(let error):
            loadState = .failed(error)
            applications = []
            selectedApplicationID = nil
            plan = nil
        }
    }

    func select(_ application: InstalledApplication) async {
        selectedApplicationID = application.id
        clearExecutionFeedback()
        await rebuildPlan()
    }

    func setMode(_ mode: UninstallMode) async {
        self.mode = mode
        clearExecutionFeedback()
        await rebuildPlan()
    }

    func setSelected(_ isSelected: Bool, for item: AppAssociatedFile) {
        guard let plan, item.isUserSelectable else { return }
        var ids = plan.selectedItemIDs
        if isSelected {
            ids.insert(item.id)
        } else {
            ids.remove(item.id)
        }
        self.plan = plan.selecting(itemIDs: ids)
        lastExecutionResult = nil
        executionNotice = nil
        executionState = .ready
    }

    func rebuildPlan(preservingExecutionFeedback: Bool = false) async {
        guard let selectedApplication else {
            plan = nil
            executionState = .idle
            return
        }
        if !preservingExecutionFeedback {
            lastExecutionResult = nil
            executionNotice = nil
        }
        executionState = .buildingPlan
        let result = await service.buildPlan(for: selectedApplication, mode: mode)
        switch result {
        case .success(let plan):
            self.plan = plan
            executionState = .ready
        case .failure(let error):
            plan = nil
            executionState = .failed(error)
        }
    }

    func executeConfirmedPlan() async {
        guard let plan else { return }
        let executedApplicationID = plan.application.id
        lastExecutionResult = nil
        executionState = .executing
        let result = await service.execute(plan: plan)
        switch result {
        case .success(let result):
            lastExecutionResult = result
            executionNotice = UninstallerExecutionNotice(result: result, applicationName: plan.application.displayName)
            executionState = .completed(result)
            await refreshAfterExecution(executedApplicationID: executedApplicationID)
        case .failure(let error):
            executionState = .failed(error)
        }
    }

    private func refreshAfterExecution(executedApplicationID: InstalledApplication.ID) async {
        loadState = .loading
        let result = await service.installedApplications(matching: query)
        switch result {
        case .success(let applications):
            self.applications = applications
            if applications.contains(where: { $0.id == selectedApplicationID }) == false {
                selectedApplicationID = applications.first?.id
            }
            loadState = .loaded

            let appWasRemovedFromList = applications.contains(where: { $0.id == executedApplicationID }) == false
            executionNotice = executionNotice?.withApplicationListRefresh(appWasRemovedFromList: appWasRemovedFromList)

            if selectedApplication == nil {
                plan = nil
                executionState = .idle
            } else {
                await rebuildPlan(preservingExecutionFeedback: true)
            }
        case .failure(let error):
            loadState = .failed(error)
            executionState = .failed(error)
        }
    }

    private func clearExecutionFeedback() {
        lastExecutionResult = nil
        executionNotice = nil
        executionState = .idle
    }
}

private struct UninstallerExecutionNotice {
    let title: String
    let message: String
    let symbolName: String
    let tint: Color

    init(result: UninstallExecutionResult, applicationName: String) {
        let total = result.itemResults.count
        if result.failedCount == 0 && result.succeededCount > 0 {
            title = "卸载已完成"
            message = "“\(applicationName)”的 \(result.succeededCount) 个项目已移到废纸篓。"
            symbolName = "checkmark.circle.fill"
            tint = .green
        } else if result.failedCount == 0 {
            title = "卸载已跳过"
            message = "“\(applicationName)”没有项目被移到废纸篓,\(result.skippedCount) 个项目已跳过。"
            symbolName = "forward.circle.fill"
            tint = .secondary
        } else if result.succeededCount > 0 {
            title = "卸载部分完成"
            message = "“\(applicationName)”已处理 \(result.succeededCount) 个项目,\(result.failedCount) 个项目需要检查权限或状态。"
            symbolName = "exclamationmark.triangle.fill"
            tint = .orange
        } else {
            title = "卸载未完成"
            message = "“\(applicationName)”的 \(total) 个项目未能移到废纸篓,请查看下方结果。"
            symbolName = "xmark.circle.fill"
            tint = .red
        }
    }

    private init(title: String, message: String, symbolName: String, tint: Color) {
        self.title = title
        self.message = message
        self.symbolName = symbolName
        self.tint = tint
    }

    func withApplicationListRefresh(appWasRemovedFromList: Bool) -> Self {
        let refreshMessage = appWasRemovedFromList
            ? "应用列表已刷新,该应用不再显示。"
            : "应用列表已刷新;如果应用仍显示,请检查下方未完成项目。"
        return Self(
            title: title,
            message: "\(message) \(refreshMessage)",
            symbolName: symbolName,
            tint: tint
        )
    }
}

private struct UninstallerContent: View {
    @Bindable var store: UninstallerStore

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

            VStack(spacing: 0) {
                UninstallerHeader(
                    isLoading: store.isBusy,
                    onRefresh: { Task { await store.refresh() } }
                )
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 14)

                HStack(spacing: 0) {
                    UninstallerApplicationList(store: store)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)

                    Divider()

                    UninstallerDetailPane(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .alert("确认卸载", isPresented: $store.isConfirmationPresented) {
            Button("取消", role: .cancel) {}
            Button(store.mode == .removeApplicationOnly ? "移到废纸篓" : "完全删除", role: .destructive) {
                Task { await store.executeConfirmedPlan() }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationMessage: String {
        guard let plan = store.plan else { return "" }
        let size = ByteCountFormatter.uninstallerString(from: plan.selectedTotalSizeBytes)
        switch plan.mode {
        case .removeApplicationOnly:
            return "将“\(plan.application.displayName)”应用本体移到废纸篓。设置、缓存和本地数据会保留。预计处理 \(size)。"
        case .removeApplicationAndAssociatedFiles:
            return "将“\(plan.application.displayName)”和已选关联文件移到废纸篓。清空废纸篓后,应用数据可能无法由 Omnipo 恢复。预计处理 \(size)。"
        }
    }
}

private struct UninstallerHeader: View {
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "trash.circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(OmnipoTheme.brandGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("应用卸载")
                    .font(.largeTitle.bold())
                Text("选择应用,预览本体与关联文件后移到废纸篓")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRefresh) {
                Label(isLoading ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
    }
}

private struct UninstallerApplicationList: View {
    @Bindable var store: UninstallerStore

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索应用或 Bundle ID", text: Binding(
                    get: { store.query.searchText },
                    set: { store.query.searchText = $0 }
                ))
                .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
            }

            Toggle("显示系统应用", isOn: Binding(
                get: { store.query.includeSystemApplications },
                set: { store.query.includeSystemApplications = $0 }
            ))
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)

            UninstallerApplicationStateView(store: store)
        }
        .padding(16)
        .onChange(of: store.query) { _, _ in
            Task { await store.refresh() }
        }
    }
}

private struct UninstallerApplicationStateView: View {
    @Bindable var store: UninstallerStore

    var body: some View {
        switch store.loadState {
        case .idle, .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("正在扫描应用")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if store.applications.isEmpty {
                ContentUnavailableView(
                    "没有匹配的应用",
                    systemImage: "app.dashed",
                    description: Text("调整搜索条件或刷新应用列表。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.applications) { application in
                            UninstallerApplicationRow(
                                application: application,
                                isSelected: store.selectedApplicationID == application.id
                            )
                            .onTapGesture {
                                Task { await store.select(application) }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        case .failed(let error):
            UninstallerErrorView(title: "应用扫描失败", error: error)
        }
    }
}

private struct UninstallerApplicationRow: View {
    let application: InstalledApplication
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            UninstallerAppIcon(application: application, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(application.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(application.bundleIdentifier ?? application.bundleURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if application.isRunning {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.orange)
                    .help("应用正在运行")
            }
        }
        .padding(10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? OmnipoTheme.brandRed.opacity(0.55) : OmnipoTheme.cardStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(application.displayName)
    }

    private var rowBackground: some ShapeStyle {
        isSelected ? AnyShapeStyle(OmnipoTheme.redTint) : AnyShapeStyle(.regularMaterial)
    }
}

private struct UninstallerDetailPane: View {
    @Bindable var store: UninstallerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let notice = store.executionNotice {
                    UninstallerExecutionNoticeBanner(notice: notice)
                }
                if let application = store.selectedApplication {
                    UninstallerAppSummary(application: application)
                    UninstallerModePicker(store: store)
                    UninstallerPrivacyStatusPanel(plan: store.plan)
                    UninstallerPlanSummary(plan: store.plan)
                    UninstallerPlanPreview(store: store)
                    UninstallerExecutionPanel(store: store)
                } else {
                    ContentUnavailableView(
                        "选择一个应用",
                        systemImage: "app.badge",
                        description: Text("从左侧列表选择应用后预览卸载计划。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

private struct UninstallerAppSummary: View {
    let application: InstalledApplication

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            UninstallerAppIcon(application: application, size: 58)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(application.displayName)
                        .font(.title.bold())
                        .lineLimit(1)
                    if application.isSystemProtected {
                        UninstallerBadge(text: "系统保护", symbol: "lock.shield", tint: .orange)
                    }
                    if application.isRunning {
                        UninstallerBadge(text: "运行中", symbol: "play.circle", tint: .orange)
                    }
                }

                Text(application.bundleIdentifier ?? "无 Bundle ID")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(application.bundleURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 10) {
                    Label(application.source.displayName, systemImage: "folder")
                    Label(ByteCountFormatter.uninstallerString(from: application.bundleSizeBytes), systemImage: "internaldrive")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
        }
    }
}

private struct UninstallerModePicker: View {
    @Bindable var store: UninstallerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("卸载模式", selection: Binding(
                get: { store.mode },
                set: { mode in Task { await store.setMode(mode) } }
            )) {
                ForEach(UninstallMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)

            Text(store.mode.userDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
        }
    }
}

private struct UninstallerPrivacyStatusPanel: View {
    let plan: AppUninstallPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("权限与隐私状态")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                UninstallerStatusLine(
                    symbol: "doc.text.magnifyingglass",
                    tint: unavailableCount > 0 ? .orange : .green,
                    title: "关联文件读取",
                    message: unavailableCount > 0
                        ? "部分位置受沙盒、TCC 或文件系统限制,已在预览中标记为不可用,不会当作无关联文件。"
                        : "当前预览未发现受限项目;路径明细只显示在本页面。"
                )
                UninstallerStatusLine(
                    symbol: "externaldrive.badge.checkmark",
                    tint: OmnipoTheme.infoCyan,
                    title: "完全磁盘访问",
                    message: "仅作为受保护路径的补充读取授权;Omnipo 不承诺也不记录全盘文件明细。"
                )
                UninstallerStatusLine(
                    symbol: "finder",
                    tint: .orange,
                    title: "Finder 自动化",
                    message: "未获得控制 Finder 授权时,相关删除会逐项返回权限不足;首版不会自动永久删除。"
                )
            }

            HStack(spacing: 10) {
                Button {
                    UninstallerSettingsOpener.openAutomationSettings()
                } label: {
                    Label("自动化设置", systemImage: "switch.2")
                }

                Button {
                    UninstallerSettingsOpener.openFullDiskAccessSettings()
                } label: {
                    Label("完全磁盘访问", systemImage: "externaldrive.badge.checkmark")
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
        }
    }

    private var unavailableCount: Int {
        plan?.unavailableItems.count ?? 0
    }
}

private struct UninstallerStatusLine: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private enum UninstallerSettingsOpener {
    static func openAutomationSettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    static func openFullDiskAccessSettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    private static func openSystemSettingsPane(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct UninstallerPlanSummary: View {
    let plan: AppUninstallPlan?

    var body: some View {
        HStack(spacing: 12) {
            UninstallerMetricTile(
                title: "已选项目",
                value: "\(plan?.selectedItems.count ?? 0)",
                symbol: "checklist.checked",
                tint: OmnipoTheme.brandRed
            )
            UninstallerMetricTile(
                title: "预计大小",
                value: ByteCountFormatter.uninstallerString(from: plan?.selectedTotalSizeBytes ?? 0),
                symbol: "externaldrive",
                tint: OmnipoTheme.infoCyan
            )
            UninstallerMetricTile(
                title: "中高风险",
                value: "\(highRiskCount)",
                symbol: "exclamationmark.triangle",
                tint: highRiskCount > 0 ? .orange : .green
            )
        }
    }

    private var highRiskCount: Int {
        guard let plan else { return 0 }
        return plan.riskSummary.mediumRiskCount + plan.riskSummary.highRiskCount
    }
}

private struct UninstallerMetricTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
        }
    }
}

private struct UninstallerPlanPreview: View {
    @Bindable var store: UninstallerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("删除预览")
                    .font(.headline)
                Spacer()
                if store.executionState == .buildingPlan {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let plan = store.plan {
                ForEach(AssociatedFileCategory.allCases) { category in
                    let items = plan.groupedItems[category] ?? []
                    if !items.isEmpty {
                        UninstallerCategorySection(
                            category: category,
                            items: items,
                            selectedIDs: plan.selectedItemIDs,
                            onSelectionChange: { item, isSelected in
                                store.setSelected(isSelected, for: item)
                            }
                        )
                    }
                }
            } else if case .failed(let error) = store.executionState {
                UninstallerErrorView(title: "卸载计划生成失败", error: error)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
    }
}

private struct UninstallerCategorySection: View {
    let category: AssociatedFileCategory
    let items: [AppAssociatedFile]
    let selectedIDs: Set<String>
    let onSelectionChange: (AppAssociatedFile, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(category.displayName)
                            .font(.callout.weight(.semibold))
                        Text("\(items.count) 项")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.12), in: Capsule())
                    }
                    Text(category.deletionConsequence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(ByteCountFormatter.uninstallerString(from: items.reduce(0) { $0 + $1.sizeBytes }))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(items) { item in
                UninstallerFileRow(
                    item: item,
                    isSelected: selectedIDs.contains(item.id),
                    onSelectionChange: { isSelected in
                        onSelectionChange(item, isSelected)
                    }
                )
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
        }
    }

    private var tint: Color {
        switch category {
        case .applicationBundle: return OmnipoTheme.brandRed
        case .cache, .logs: return OmnipoTheme.infoCyan
        case .preferences, .savedApplicationState: return .blue
        case .applicationSupport, .container, .groupContainer: return .orange
        case .launchAgent: return .purple
        case .other: return .secondary
        }
    }

}

private struct UninstallerFileRow: View {
    let item: AppAssociatedFile
    let isSelected: Bool
    let onSelectionChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isSelected },
            set: { onSelectionChange($0) }
        )) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.displayName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        UninstallerRiskBadge(risk: item.riskLevel)
                    }

                    if let reason = item.unavailableReason {
                        Label(reason.userDescription, systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(reason.userDescription)
                    }

                    Text(item.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.url.path)
                }

                Spacer(minLength: 10)

                Text(ByteCountFormatter.uninstallerString(from: item.sizeBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!item.isUserSelectable)
        .help(helpText)
        .accessibilityElement(children: .combine)
    }

    private var helpText: String {
        if let reason = item.unavailableReason {
            return "\(item.displayName): \(reason.userDescription)"
        }
        if item.riskLevel == .high {
            return "\(item.displayName): 高风险项目不会默认选中,确认归属后可手动勾选。"
        }
        return item.url.path
    }
}

private struct UninstallerExecutionPanel: View {
    @Bindable var store: UninstallerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    store.isConfirmationPresented = true
                } label: {
                    Label(actionTitle, systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canExecute)

                if store.executionState == .executing {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }

            switch store.executionState {
            case .failed(let error):
                UninstallerErrorView(title: "卸载执行失败", error: error)
            default:
                if let result = store.lastExecutionResult {
                    UninstallerExecutionResultView(result: result)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
        }
    }

    private var canExecute: Bool {
        guard let plan = store.plan else { return false }
        return !plan.selectedItems.isEmpty && store.executionState != .executing && store.executionState != .buildingPlan
    }

    private var actionTitle: String {
        store.mode == .removeApplicationOnly ? "卸载应用" : "完全删除所选项目"
    }
}

private struct UninstallerExecutionResultView: View {
    let result: UninstallExecutionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                UninstallerBadge(text: "成功 \(result.succeededCount)", symbol: "checkmark.circle", tint: .green)
                UninstallerBadge(text: "失败 \(result.failedCount)", symbol: "xmark.circle", tint: result.failedCount > 0 ? .red : .secondary)
                UninstallerBadge(text: "跳过 \(result.skippedCount)", symbol: "forward.circle", tint: .secondary)
            }

            ForEach(result.itemResults) { itemResult in
                HStack(spacing: 8) {
                    Image(systemName: itemResult.status.symbolName)
                        .foregroundStyle(itemResult.status.tint)
                        .frame(width: 20)
                    Text(itemResult.item.displayName)
                        .lineLimit(1)
                    Spacer()
                    Text(itemResult.status.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(itemResult.status.tint)
                }
                .font(.callout)
            }
        }
    }
}

private struct UninstallerExecutionNoticeBanner: View {
    let notice: UninstallerExecutionNotice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(notice.tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.headline)
                Text(notice.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(notice.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(notice.tint.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct UninstallerAppIcon: View {
    let application: InstalledApplication
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: max(6, size * 0.22), style: .continuous))
            } else {
                Image(systemName: "app")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(OmnipoTheme.brandRed)
                    .frame(width: size, height: size)
                    .background(OmnipoTheme.redTint, in: RoundedRectangle(cornerRadius: max(6, size * 0.22), style: .continuous))
            }
        }
        .frame(width: size, height: size)
        .task(id: application.bundleURL.path) {
            image = NSWorkspace.shared.icon(forFile: application.bundleURL.path)
        }
    }
}

private struct UninstallerBadge: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct UninstallerRiskBadge: View {
    let risk: AssociatedFileRiskLevel

    var body: some View {
        Text(risk.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .help(helpText)
    }

    private var tint: Color {
        switch risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    private var helpText: String {
        switch risk {
        case .low:
            return "低风险:通常可安全移到废纸篓。"
        case .medium:
            return "中风险:可能包含设置、容器或本地数据,请确认后再删除。"
        case .high:
            return "高风险:默认不选中;可能包含高敏数据、共享数据或归属不明确内容。"
        }
    }
}

private struct UninstallerErrorView: View {
    let title: String
    let error: AppError

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.red)
            Text(error.userDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
        }
    }
}

private extension ByteCountFormatter {
    static func uninstallerString(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesActualByteCount = false
        return formatter.string(fromByteCount: bytes)
    }
}

private extension UninstallExecutionItemStatus {
    var displayName: String {
        switch self {
        case .succeeded: return "成功"
        case .failed: return "失败"
        case .skipped: return "已跳过"
        case .cancelled: return "已取消"
        case .insufficientPermission: return "权限不足"
        case .systemProtected: return "系统保护"
        }
    }

    var symbolName: String {
        switch self {
        case .succeeded: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .skipped: return "forward.circle"
        case .cancelled: return "stop.circle"
        case .insufficientPermission: return "lock.circle"
        case .systemProtected: return "lock.shield"
        }
    }

    var tint: Color {
        switch self {
        case .succeeded: return .green
        case .failed, .insufficientPermission, .systemProtected: return .red
        case .skipped, .cancelled: return .secondary
        }
    }
}

#Preview {
    UninstallerView()
        .environment(DependencyContainer.production())
        .frame(width: 980, height: 680)
}
