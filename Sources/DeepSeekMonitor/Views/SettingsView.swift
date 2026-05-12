import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Settings View
//
// 设置面板内容:
// 1. API Key 输入 & 验证
// 2. 刷新间隔配置
// 3. 缓存管理（清空 / 查看状态）

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var exportAutomation = UsageExportAutomationService.shared
    @Environment(\.colorScheme) private var colorScheme

    // API Key
    @State private var apiKeyInput: String = ""
    @State private var isVerifying = false
    @State private var verifyStatus: VerifyStatus = .idle
    @State private var usageImportStatus: UsageImportStatus = .idle

    // 刷新间隔选项
    private let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("30 秒", 30),
        ("60 秒", 60),
        ("2 分钟", 120),
        ("5 分钟", 300),
    ]

    private let panelResidenceOptions: [(label: String, value: TimeInterval)] = [
        ("10 秒", 10),
        ("20 秒", 20),
        ("30 秒", 30),
    ]

    private let exportIntervalOptions: [(label: String, value: TimeInterval)] = [
        ("1 分钟", 60),
        ("5 分钟", 300),
        ("10 分钟", 600),
        ("半小时", 1800),
    ]

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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ── Header ──
                headerSection
                Divider().padding(.vertical, 16)

                // ── API Key ──
                apiKeySection
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
        }
        .frame(width: 420, height: 620)
        .background(Theme.windowBackground(for: colorScheme))
        .onAppear {
            // 重新打开设置时回填已保存的 Key，避免重复输入
            apiKeyInput = DeepSeekService.shared.apiKey ?? ""
            verifyStatus = .idle
            usageImportStatus = .idle
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

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("API Key", systemImage: "key.fill")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("用于调用 DeepSeek API 获取余额和用量数据。当前本地构建版本会保存在应用本地设置中。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("API Key 只在当前这台 Mac 本地保留。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text("本地位置：~/Library/Preferences/com.deepseek.monitor.plist")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }

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
                        viewModel.clearAPIKey()
                        apiKeyInput = ""
                        verifyStatus = .idle
                        usageImportStatus = .idle
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
            Label("自动刷新", systemImage: "timer")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("每隔多久自动从 DeepSeek API 拉取最新数据")
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

    // MARK: - Cache

    private var usageImportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("用量导入", systemImage: "chart.line.text.clipboard")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("实时用量接口暂未开放。自动网页导出的文件会先进入 App 的专用导入目录，并在检测到新文件后自动解压导入。手动扫描也只会检查这个专用导入目录。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(action: triggerAutoScan) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("立即扫描导入目录")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(action: importUsageCSV) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("导入 amount CSV")
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

            VStack(alignment: .leading, spacing: 6) {
                Text("专用导入目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 8) {
                    Text(importFolderPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(3)

                    Spacer(minLength: 0)

                    Button(action: openImportFolder) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("打开文件夹")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }

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

            Text("首次需要你手动登录一次 DeepSeek 平台。登录后，App 会按你设定的频率在后台静默刷新 usage 页面并尝试导出，正常情况下不会主动弹出网页窗口，下载后的 ZIP 会继续自动导入。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("启用自动导出", isOn: Binding(
                get: { exportAutomation.isEnabled },
                set: { exportAutomation.isEnabled = $0 }
            ))
            .toggleStyle(.switch)

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
                        Text("立即尝试导出")
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

            if let trace = exportAutomation.lastClickTraceSummary {
                Text("最近点击: \(trace)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(4)
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
                    LocalCache.shared.clearAll()
                    viewModel.clearAPIKey()
                    apiKeyInput = ""
                    verifyStatus = .idle
                    usageImportStatus = .idle
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("清空所有缓存")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                if let lastUpdated = viewModel.lastUpdated {
                    Text("上次缓存: \(lastUpdated.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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
                    Text("版本 1.2.0")
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

        // 保存到服务
        viewModel.setAPIKey(apiKeyInput)

        // 验证：发起一次余额查询
        Task {
            do {
                let service = DeepSeekService.shared
                let balance = try await service.fetchBalance()
                let balanceText = balance.balanceInfos.first?.totalBalance ?? "?"
                verifyStatus = .success("验证成功，当前余额: ¥\(balanceText)")
                isVerifying = false
            } catch let error as APIError {
                verifyStatus = .failure(error.errorDescription ?? "未知错误")
                isVerifying = false
            } catch {
                verifyStatus = .failure(error.localizedDescription)
                isVerifying = false
            }
        }
    }

    private func importUsageCSV() {
        let panel = NSOpenPanel()
        panel.title = "选择 DeepSeek amount CSV"
        panel.message = "请选择从 DeepSeek Usage 导出并解压后的 amount CSV 文件"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try viewModel.importUsageCSV(from: url)
            usageImportStatus = .success("导入成功，已更新用量和趋势")
        } catch let error as UsageCSVImportError {
            usageImportStatus = .failure(error.errorDescription ?? "导入失败")
        } catch {
            usageImportStatus = .failure(error.localizedDescription)
        }
    }

    private func triggerAutoScan() {
        viewModel.autoImportUsageIfNeeded()
        if viewModel.totalTokens > 0 {
            usageImportStatus = .success("扫描完成，已更新用量数据")
        } else if let warning = viewModel.warningMessage, warning.contains("自动导入") {
            usageImportStatus = .failure(warning)
        } else {
            usageImportStatus = .failure("没有发现可导入的新 DeepSeek ZIP/CSV")
        }
    }

    private var importFolderPath: String {
        guard let path = try? UsageAutoImportService.incomingFolderURL().path else {
            return "无法读取目录路径"
        }

        let homePath = NSHomeDirectory()
        if path.hasPrefix(homePath) {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }

    private func openImportFolder() {
        guard let url = try? UsageAutoImportService.incomingFolderURL() else {
            usageImportStatus = .failure("无法打开专用导入目录")
            return
        }

        NSWorkspace.shared.open(url)
    }
}
