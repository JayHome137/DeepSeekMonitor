import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ServiceManagement

// MARK: - Settings View
//
// 设置面板内容:
// 1. API Key 输入 & 验证
// 2. 刷新间隔配置
// 3. 缓存管理（清空 / 查看状态）

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var softwareUpdateController: SoftwareUpdateController
    @ObservedObject private var exportAutomation = UsageExportAutomationService.shared
    @Environment(\.colorScheme) private var colorScheme

    // API Key
    @State private var apiKeyInput: String = ""
    @State private var isVerifying = false
    @State private var verifyStatus: VerifyStatus = .idle
    @State private var usageImportStatus: UsageImportStatus = .idle
    @State private var cacheStatusMessage: String?
    @State private var scrollResetToken = 0
    @State private var isLaunchAtLogin = false

    // 刷新间隔选项
    private let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("30 秒", 30),
        ("60 秒", 60),
        ("2 分钟", 120),
        ("5 分钟", 300),
    ]

    private let panelResidenceOptions: [(label: String, value: TimeInterval)] = [
        ("3 秒", 3),
        ("5 秒", 5),
        ("10 秒", 10),
    ]

    private let exportIntervalOptions: [(label: String, value: TimeInterval)] = [
        ("5 分钟", 300),
        ("10 分钟", 600),
        ("半小时", 1800),
    ]

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "--"
        return "版本 \(version)"
    }

    enum VerifyStatus: Equatable {
        case idle
        case verifying
        case success(String)
        case failure(String)
    }

    enum UsageImportStatus: Equatable {
        case idle
        case success(String)
        case failure(String)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                // ── Header ──
                headerSection
                Divider().padding(.vertical, 16)

                // ── API Key ──
                apiKeySection
                Divider().padding(.vertical, 16)

                // ── Desktop Widget ──
                nativeWidgetSection
                Divider().padding(.vertical, 16)

                // ── Launch at Login ──
                launchAtLoginSection
                Divider().padding(.vertical, 16)

                // ── Software Update ──
                softwareUpdateSection
                Divider().padding(.vertical, 16)

                // ── Refresh ──
                refreshIntervalSection
                Divider().padding(.vertical, 16)

                // ── Panel Residence ──
                panelResidenceSection
                Divider().padding(.vertical, 16)

                // ── Usage Import ──
                usageImportSection
                Divider().padding(.vertical, 16)

                // ── Usage Export Automation ──
                usageExportAutomationSection
                Divider().padding(.vertical, 16)

                // ── Cache ──
                cacheSection
                Divider().padding(.vertical, 16)

                // ── Footer ──
                aboutSection
            }
            .padding(20)
            .id(scrollResetToken)
        }
        .defaultScrollAnchor(.top)
        .frame(width: 420, height: 620)
        .background(.ultraThinMaterial)
        .onAppear {
            // 重新打开设置时回填已保存的 Key，避免重复输入
            apiKeyInput = viewModel.apiKey ?? ""
            if let storageError = viewModel.apiKeyStorageError {
                verifyStatus = .failure(storageError)
            } else {
                verifyStatus = .idle
            }
            usageImportStatus = .idle
            cacheStatusMessage = nil
            isLaunchAtLogin = SMAppService.mainApp.status == .enabled
            scrollResetToken += 1
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.brandFaint)
                    .frame(width: 36, height: 36)
                BrandIconView(size: 22)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("DeepSeek Monitor")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("设置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - API Key

    private var nativeWidgetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("桌面小组件", systemImage: "rectangle.on.rectangle")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("控制系统原生 WidgetKit 小组件的数据同步。关闭后，已添加的小组件会显示停用状态。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("启用原生小组件数据", isOn: $viewModel.isNativeWidgetEnabled)
                .toggleStyle(.switch)
                .scaleEffect(0.8, anchor: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("开机自启", systemImage: "power")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("开启后，每次登录 Mac 时自动启动 DeepSeek Monitor，确保桌面小组件数据保持最新。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("登录时自动启动", isOn: Binding(
                get: { isLaunchAtLogin },
                set: { newValue in
                    isLaunchAtLogin = newValue
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        isLaunchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            ))
            .toggleStyle(.switch)
            .scaleEffect(0.8, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var softwareUpdateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("软件更新", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 10) {
                Button(action: softwareUpdateController.checkForUpdates) {
                    HStack(spacing: 5) {
                        if softwareUpdateController.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(softwareUpdateController.isChecking ? "正在检查" : "检查更新")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
                .disabled(
                    !softwareUpdateController.canCheckForUpdates ||
                    softwareUpdateController.isChecking
                )

                Text("当前版本 \(softwareUpdateController.currentVersionText)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            softwareUpdateStatus
        }
    }

    @ViewBuilder
    private var softwareUpdateStatus: some View {
        switch softwareUpdateController.state {
        case .idle:
            EmptyView()
        case .unavailable(let message):
            Label(message, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.orange)
        case .checking:
            Text("正在连接安全更新源…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .upToDate:
            Label("目前已是最新版", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .updateAvailable(let version):
            Label("发现新版本 \(version)，请在更新窗口中确认安装", systemImage: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .downloading(let version):
            Label("正在下载版本 \(version)", systemImage: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .installing(let version):
            Label("正在安装版本 \(version)", systemImage: "shippingbox.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("API Key", systemImage: "key.fill")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("用于调用 DeepSeek API 获取余额和用量数据，并通过 macOS 钥匙串安全保存在本机。")
                .font(.caption)
                .foregroundStyle(.secondary)

            // 输入框
            HStack(spacing: 8) {
                SecureField("sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .disableAutocorrection(true)
                    .labelsHidden()

                // 粘贴按钮
                Button(action: {
                    if let string = NSPasteboard.general.string(forType: .string) {
                        apiKeyInput = string
                    }
                }) {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("从剪贴板粘贴")
            }

            // 状态反馈
            HStack {
                // 验证 & 保存
                Button(action: verifyAndSave) {
                    if isVerifying {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Text("验证并保存")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
                .disabled(apiKeyInput.isEmpty || isVerifying)

                Spacer()

                // Key 状态
                if viewModel.hasAPIKey {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .imageScale(.small)
                        Text("已配置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 清空 Key
                if viewModel.hasAPIKey {
                    Button("清除 Key", role: .destructive) {
                        clearSavedAPIKey()
                    }
                    .font(.caption)
                    .controlSize(.small)
                }
            }

            // 验证结果
            switch verifyStatus {
            case .idle:
                EmptyView()
            case .verifying:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("正在验证 API Key...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .success(let msg):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            case .failure(let msg):
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .imageScale(.small)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Refresh Interval

    private var refreshIntervalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("余额自动刷新", systemImage: "timer")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("每隔多久从 DeepSeek API 刷新余额；用量由下方网页导出单独同步。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(intervalOptions, id: \.value) { option in
                    intervalButton(option: option)
                }
            }
        }
    }

    private func intervalButton(option: (label: String, value: TimeInterval)) -> some View {
        let isSelected = viewModel.refreshInterval == option.value
        return Button(action: {
            viewModel.refreshInterval = option.value
        }) {
            Text(option.label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
    }

    private var panelResidenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("面板驻留时间", systemImage: "hourglass")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("点击菜单栏图标后，面板自动停留多久再收起。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(panelResidenceOptions, id: \.value) { option in
                    panelResidenceButton(option: option)
                }
            }
        }
    }

    private func panelResidenceButton(option: (label: String, value: TimeInterval)) -> some View {
        let isSelected = viewModel.panelResidenceSeconds == option.value
        return Button(action: {
            viewModel.panelResidenceSeconds = option.value
        }) {
            Text(option.label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
    }

    // MARK: - Usage Import

    private var usageImportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("用量导入", systemImage: "chart.line.text.clipboard")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("自动网页导出是主要同步方式。手动导入用于登录失效、网页结构变化或补录历史数据，支持官方本月、近 7 天和近 30 天 ZIP/CSV。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(action: importUsageExport) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("手动导入（故障兜底）")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)

                if viewModel.totalTokens > 0 {
                    Text("当前已显示用量数据")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            DisclosureGroup("故障排查") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("自动导入失败的文件会保留在 failed 子目录，不会被直接删除。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Button(action: openImportFolder) {
                        Label("打开导入目录", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }
            .font(.caption)

            switch usageImportStatus {
            case .idle:
                EmptyView()
            case .success(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failure(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var usageExportAutomationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("自动网页导出", systemImage: "globe")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("首次需要你手动登录一次 DeepSeek 平台。登录后，App 会按设定频率静默导出并导入本月用量 ZIP。用量日期以官方导出文件携带的时区为准，网页数据可能延迟约 5 分钟。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("启用自动导出", isOn: Binding(
                get: { exportAutomation.isEnabled },
                set: { exportAutomation.isEnabled = $0 }
            ))
            .toggleStyle(.switch)
            .scaleEffect(0.8, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("自动导出频率")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(exportIntervalOptions, id: \.value) { option in
                        exportIntervalButton(option: option)
                    }
                }
            }

            HStack(spacing: 10) {
                Button(action: {
                    exportAutomation.openLoginWindow()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.key")
                        Text("打开登录页")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    exportAutomation.triggerManualExport()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                        Text("立即同步本月")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
            }

            HStack(spacing: 6) {
                Image(systemName: exportAutomation.isLoggedIn ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(exportAutomation.isLoggedIn ? .green : .secondary)
                    .imageScale(.small)
                Text(exportAutomation.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let fileName = exportAutomation.lastDownloadFileName {
                Text("最近下载: \(fileName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

        }
    }

    private func exportIntervalButton(option: (label: String, value: TimeInterval)) -> some View {
        let isSelected = exportAutomation.autoExportIntervalSeconds == option.value
        return Button(action: {
            exportAutomation.autoExportIntervalSeconds = option.value
        }) {
            Text(option.label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
    }

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("数据管理", systemImage: "externaldrive")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("本地缓存的上次数据快照，App 重启后会立即显示缓存数据")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(action: {
                    clearCachedData()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("清空所有缓存")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                VStack(alignment: .leading, spacing: 2) {
                    if let balanceUpdatedAt = viewModel.balanceLastUpdated {
                        Text("余额更新: \(balanceUpdatedAt.formatted(date: .abbreviated, time: .standard))")
                    }
                    if let usageUpdatedAt = viewModel.usageLastUpdated {
                        Text("用量导入: \(usageUpdatedAt.formatted(date: .abbreviated, time: .standard))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            if let cacheStatusMessage {
                Label(cacheStatusMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(spacing: 6) {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    BrandIconView(size: 28)

                    Text("DeepSeek Monitor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appVersionText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func verifyAndSave() {
        guard !apiKeyInput.isEmpty else { return }

        isVerifying = true
        verifyStatus = .verifying

        Task {
            defer { isVerifying = false }
            do {
                let balance = try await viewModel.validateAndSaveAPIKey(apiKeyInput)
                let info = balance.preferredBalanceInfo
                let balanceValue = Double(info?.totalBalance ?? "") ?? 0
                let currencyCode = normalizedCurrencyCode(info?.currency ?? "CNY")
                verifyStatus = .success("验证成功，当前余额: \(formattedCurrency(balanceValue, currencyCode: currencyCode))")
                apiKeyInput = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch let error as APIError {
                verifyStatus = .failure(error.errorDescription ?? "未知错误")
            } catch {
                verifyStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func clearSavedAPIKey() {
        do {
            try viewModel.clearAPIKey()
            apiKeyInput = ""
            verifyStatus = .idle
            usageImportStatus = .idle
        } catch {
            verifyStatus = .failure(error.localizedDescription)
        }
    }

    private func clearCachedData() {
        viewModel.clearCachedData()
        usageImportStatus = .idle
        cacheStatusMessage = "缓存已清空，API Key 已保留"
    }

    private func importUsageExport() {
        let panel = NSOpenPanel()
        panel.title = "选择 DeepSeek Usage ZIP/CSV"
        panel.message = "优先选择官方导出的 ZIP，以同时读取用量和精确费用"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.zip, .commaSeparatedText, .plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let importedFiles = try viewModel.importUsageExport(from: url)
            let details = importedFiles.joined(separator: " + ")
            usageImportStatus = .success("导入成功：\(details)")
        } catch let error as UsageCSVImportError {
            usageImportStatus = .failure(error.errorDescription ?? "导入失败")
        } catch {
            usageImportStatus = .failure(error.localizedDescription)
        }
    }

    private func openImportFolder() {
        guard let url = try? UsageAutoImportService.incomingFolderURL() else {
            usageImportStatus = .failure("无法打开专用导入目录")
            return
        }

        NSWorkspace.shared.open(url)
    }
}
