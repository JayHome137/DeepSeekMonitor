import Foundation
import Combine
import Dispatch

// MARK: - Dashboard ViewModel
//
// 核心状态管理层，负责：
// 1. 调用 DeepSeekService 获取数据
// 2. 定时轮询（默认每 60 秒自动刷新）
// 3. 数据聚合（按模型分组、统计汇总）
// 4. 对外暴露 @Published 属性供 UI 绑定

@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: - Published: 余额

    /// 原始余额信息
    @Published private(set) var balanceInfo: BalanceInfo?
    /// 账户是否可用（余额 > 0）
    @Published private(set) var isAccountAvailable: Bool = false
    /// 总余额（元）
    @Published private(set) var totalBalance: Double = 0
    /// 赠送余额（元）
    @Published private(set) var grantedBalance: Double = 0
    /// 充值余额（元）
    @Published private(set) var toppedUpBalance: Double = 0
    /// 当日消耗（元）
    @Published private(set) var currentDayCost: Double = 0
    /// 本月消费（元）
    @Published private(set) var currentMonthCost: Double = 0

    // MARK: - Published: 用量

    /// V4 Flash 用量汇总
    @Published private(set) var flashUsage: ModelUsageSummary?
    /// V4 Pro 用量汇总
    @Published private(set) var proUsage: ModelUsageSummary?
    /// 每日用量明细（用于趋势图）
    @Published private(set) var dailyUsage: [Date: Int] = [:]
    /// V4 Flash 按日明细
    @Published private(set) var flashDailyUsage: [ModelDailyUsagePoint] = []
    /// V4 Pro 按日明细
    @Published private(set) var proDailyUsage: [ModelDailyUsagePoint] = []

    // MARK: - Published: 状态

    /// 是否正在加载
    @Published private(set) var isLoading: Bool = false
    /// 错误信息
    @Published private(set) var errorMessage: String?
    /// 非阻断性提示（例如部分数据接口不可用）
    @Published private(set) var warningMessage: String?
    /// 上次成功刷新时间
    @Published private(set) var lastUpdated: Date?
    /// 是否已配置 API Key
    @Published private(set) var hasAPIKey: Bool = false
    /// 面板驻留时间（秒）
    @Published var panelResidenceSeconds: TimeInterval = UserDefaults.standard.double(forKey: "panel_residence_seconds") {
        didSet {
            let normalized = Self.normalizedPanelResidence(panelResidenceSeconds)
            if normalized != panelResidenceSeconds {
                panelResidenceSeconds = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: "panel_residence_seconds")
        }
    }
    /// 是否启用系统原生 WidgetKit 小组件数据
    @Published var isNativeWidgetEnabled: Bool = LocalCache.shared.isNativeWidgetEnabled {
        didSet {
            LocalCache.shared.setNativeWidgetEnabled(isNativeWidgetEnabled)
        }
    }

    // MARK: - Configuration

    /// 自动刷新间隔（秒），默认 60 秒
    var refreshInterval: TimeInterval = 60 {
        didSet { restartTimer() }
    }

    /// 用量查询回溯天数
    var usageLookbackDays: Int = 7

    // MARK: - Private

    private let service = DeepSeekService.shared
    private var timer: Timer?
    private var importMonitors: [DirectoryChangeMonitor] = []
    private var importDebounceWorkItem: DispatchWorkItem?
    private var isRefreshing = false

    // MARK: - Init

    init() {
        panelResidenceSeconds = Self.normalizedPanelResidence(panelResidenceSeconds)
        hasAPIKey = service.hasAPIKey
        let cachedRecords = LocalCache.shared.loadUsageRecords()
        if cachedRecords.isEmpty {
            UsageAutoImportService.resetRememberedImport()
        } else if cachedRecords.contains(where: { $0.totalTokens > 0 }) &&
                    cachedRecords.allSatisfy({ $0.requestCount == 0 }) {
            UsageAutoImportService.resetRememberedImport()
        }
        loadCachedData()
    }

    nonisolated deinit {
        // 在 deinit 中手动清理定时器，避免 actor 隔离问题
        Task { @MainActor [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
            self?.stopImportMonitors()
        }
    }

    // MARK: - Auto Refresh

    /// 启动定时刷新（启动时立即刷新一次）
    func startAutoRefresh() {
        stopAutoRefresh()

        // 立即执行首次刷新
        Task { await refresh() }
        autoImportUsageIfNeeded()
        startImportMonitors()

        // 创建定时器
        timer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.refresh()
            }
        }
    }

    /// 停止定时刷新
    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
        stopImportMonitors()
    }

    /// 重启定时器（修改间隔后调用）
    private func restartTimer() {
        guard timer != nil else { return }
        startAutoRefresh()
    }

    private func startImportMonitors() {
        stopImportMonitors()

        guard let urls = try? UsageAutoImportService.watchedFolderURLs() else { return }
        importMonitors = urls.map { url in
            let monitor = DirectoryChangeMonitor(url: url) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleAutoImportFromFolderChange()
                }
            }
            monitor.start()
            return monitor
        }
    }

    private func stopImportMonitors() {
        importDebounceWorkItem?.cancel()
        importDebounceWorkItem = nil
        importMonitors.forEach { $0.stop() }
        importMonitors.removeAll()
    }

    private func scheduleAutoImportFromFolderChange() {
        importDebounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.autoImportUsageIfNeeded()
        }

        importDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private static func normalizedPanelResidence(_ value: TimeInterval) -> TimeInterval {
        let allowed: [TimeInterval] = [3, 5, 10]
        return allowed.contains(value) ? value : 10
    }

    // MARK: - Refresh

    /// 手动刷新数据
    func refresh() async {
        // 防止并发刷新
        guard !isRefreshing else { return }
        defer { isRefreshing = false }
        isRefreshing = true

        // 没有 API Key 时不请求
        guard hasAPIKey else {
            errorMessage = "请先配置 API Key"
            warningMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        warningMessage = nil

        do {
            // 并行请求余额 + 用量
            async let balanceTask = try service.fetchBalance()
            async let usageTask = try service.fetchRecentUsage(days: usageLookbackDays)

            let balanceResp = try await balanceTask

            // ── 更新余额 ──
            if let info = balanceResp.balanceInfos.first {
                balanceInfo = info
                isAccountAvailable = balanceResp.isAvailable
                totalBalance = Double(info.totalBalance) ?? 0
                grantedBalance = Double(info.grantedBalance) ?? 0
                toppedUpBalance = Double(info.toppedUpBalance) ?? 0
            }

            do {
                let usageResp = try await usageTask

                // ── 更新用量（按模型聚合） ──
                aggregateUsage(usageResp.data)
                LocalCache.shared.saveUsageRecords(usageResp.data)

                // ── 构建每日用量字典（用于趋势图） ──
                buildDailyUsage(from: usageResp.data)
            } catch {
                handleUsageFailure(error)
            }

            // ── 持久化到本地缓存 ──
            lastUpdated = Date()
            saveCache()

        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - API Key

    /// 设置 API Key 并立即刷新
    func setAPIKey(_ key: String) {
        service.apiKey = key
        hasAPIKey = service.hasAPIKey
        Task { await refresh() }
    }

    /// 清除 API Key 并重置状态
    func clearAPIKey() {
        service.clearAPIKey()
        hasAPIKey = false

        // 清除本地缓存
        LocalCache.shared.clearAll()
        UsageAutoImportService.resetRememberedImport()

        // 重置所有数据
        balanceInfo = nil
        isAccountAvailable = false
        totalBalance = 0
        grantedBalance = 0
        toppedUpBalance = 0
        currentDayCost = 0
        currentMonthCost = 0
        flashUsage = nil
        proUsage = nil
        dailyUsage = [:]
        flashDailyUsage = []
        proDailyUsage = []
        lastUpdated = nil
        errorMessage = nil
        warningMessage = nil
    }

    func importUsageCSV(from url: URL) throws {
        let records = try UsageCSVImporter.importRecords(from: url)
        LocalCache.shared.saveUsageRecords(records)
        applyUsageRecords(records)
        warningMessage = "已显示从 CSV 导入的用量记录"
        lastUpdated = Date()
        saveCache()
    }

    func autoImportUsageIfNeeded() {
        do {
            guard let candidate = try UsageAutoImportService.nextImportCandidate() else { return }
            try importUsageCSV(from: candidate.preparedCSVURL)
            UsageAutoImportService.markImported(candidate.fingerprint)
            try? UsageAutoImportService.cleanupImportedSources(keeping: candidate.sourceURL)
        } catch {
            if let candidate = try? UsageAutoImportService.nextImportCandidate() {
                warningMessage = "自动导入 \(candidate.sourceName) -> \(candidate.selectedCSVName) 失败：\(error.localizedDescription)"
            } else {
                warningMessage = "自动导入用量失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - Computed

    /// 总 Token 消耗（所有模型合计）
    var totalTokens: Int {
        (flashUsage?.totalTokens ?? 0) + (proUsage?.totalTokens ?? 0)
    }

    /// 总费用（所有模型合计，单位：元）
    var totalCost: Double {
        let flash = Double(flashUsage?.costInCents ?? 0) / 100.0
        let pro   = Double(proUsage?.costInCents ?? 0) / 100.0
        return flash + pro
    }

    var currentMonthCostFormatted: String {
        String(format: "¥%.2f", currentMonthCost)
    }

    /// 上次刷新时间的格式化文本
    var lastUpdatedFormatted: String {
        guard let date = lastUpdated else { return "尚未刷新" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }

    /// 是否正在显示错误
    var hasError: Bool {
        errorMessage != nil
    }

    /// DeepSeek 公开 API 当前是否不支持用量查询
    var isUsageUnavailable: Bool {
        warningMessage == APIError.usageEndpointUnavailable.errorDescription
    }

    // MARK: - Chart Data

    /// 趋势图数据点
    struct ChartDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let dayLabel: String
        let tokens: Int

        var formattedTokens: String {
            if tokens >= 1_000_000 {
                String(format: "%.1fM", Double(tokens) / 1_000_000)
            } else if tokens >= 1_000 {
                String(format: "%.1fK", Double(tokens) / 1_000)
            } else {
                "\(tokens)"
            }
        }
    }

    /// 最近 N 天的趋势数据（按日期排序）
    var chartData: [ChartDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M/d"
            return f
        }()

        // 生成最近 usageLookbackDays 天的数据
        var points: [ChartDataPoint] = []
        for dayOffset in (0..<usageLookbackDays).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                continue
            }
            let normalizedDate = calendar.startOfDay(for: date)
            let tokens = dailyUsage[normalizedDate] ?? 0
            points.append(ChartDataPoint(
                date: normalizedDate,
                dayLabel: dayFormatter.string(from: date),
                tokens: tokens
            ))
        }
        return points
    }

    func summary(for model: DeepSeekModel) -> ModelUsageSummary? {
        switch model {
        case .flash: return flashUsage
        case .pro:   return proUsage
        }
    }

    func dailyPoints(for model: DeepSeekModel) -> [ModelDailyUsagePoint] {
        switch model {
        case .flash: return flashDailyUsage
        case .pro:   return proDailyUsage
        }
    }

    // MARK: - Helpers

    /// 按模型聚合用量
    private func aggregateUsage(_ records: [UsageRecord]) {
        let flashRecords = records.filter { $0.modelName == DeepSeekModel.flash.rawValue }
        let proRecords   = records.filter { $0.modelName == DeepSeekModel.pro.rawValue }

        flashUsage = summary(for: flashRecords, model: .flash)
        proUsage = summary(for: proRecords, model: .pro)
    }

    /// 构建按日期的 Token 消耗字典
    private func buildDailyUsage(from records: [UsageRecord]) {
        var totalByDate: [Date: Int] = [:]
        var flashByDate: [Date: (tokens: Int, hit: Int, miss: Int, output: Int, requests: Int)] = [:]
        var proByDate: [Date: (tokens: Int, hit: Int, miss: Int, output: Int, requests: Int)] = [:]

        for record in records {
            guard let day = recordDay(from: record.date) else { continue }
            totalByDate[day, default: 0] += record.totalTokens

            switch normalizedModelName(record.modelName) {
            case .flash:
                var value = flashByDate[day] ?? (0, 0, 0, 0, 0)
                value.tokens += record.totalTokens
                value.hit += record.inputCacheHitTokens
                value.miss += record.inputCacheMissTokens
                value.output += record.completionTokens
                value.requests += record.requestCount
                flashByDate[day] = value
            case .pro:
                var value = proByDate[day] ?? (0, 0, 0, 0, 0)
                value.tokens += record.totalTokens
                value.hit += record.inputCacheHitTokens
                value.miss += record.inputCacheMissTokens
                value.output += record.completionTokens
                value.requests += record.requestCount
                proByDate[day] = value
            case nil:
                continue
            }
        }

        dailyUsage = totalByDate
        flashDailyUsage = buildModelDailyPoints(from: flashByDate)
        proDailyUsage = buildModelDailyPoints(from: proByDate)
    }

    private func clearUsageData() {
        flashUsage = nil
        proUsage = nil
        dailyUsage = [:]
        flashDailyUsage = []
        proDailyUsage = []
        currentMonthCost = 0
        currentDayCost = 0
    }

    private func applyUsageRecords(_ records: [UsageRecord]) {
        aggregateUsage(records)
        buildDailyUsage(from: records)
        currentDayCost = computeCurrentDayCost(from: records)
        currentMonthCost = computeCurrentMonthCost(from: records)
    }

    private func restoreImportedUsageIfAvailable(unavailableMessage: String) -> Bool {
        let cachedRecords = LocalCache.shared.loadUsageRecords()
        guard cachedRecords.isEmpty == false else { return false }

        applyUsageRecords(cachedRecords)
        warningMessage = "\(unavailableMessage)，已显示导入的 CSV 记录"
        return true
    }

    private func handleUsageFailure(_ error: Error) {
        if let apiError = error as? APIError,
           case .usageEndpointUnavailable = apiError {
            if restoreImportedUsageIfAvailable(unavailableMessage: apiError.errorDescription ?? "实时用量不可用") == false {
                clearUsageData()
                warningMessage = apiError.errorDescription
            }
            return
        }

        if let apiError = error as? APIError {
            if restoreImportedUsageIfAvailable(unavailableMessage: "实时用量同步失败") == false {
                warningMessage = "用量同步失败：\(apiError.errorDescription ?? "未知错误")"
            }
        } else {
            if restoreImportedUsageIfAvailable(unavailableMessage: "实时用量同步失败") == false {
                warningMessage = "用量同步失败：\(error.localizedDescription)"
            }
        }
    }

    func loadImportedUsageIfAvailable() {
        let cachedRecords = LocalCache.shared.loadUsageRecords()
        guard cachedRecords.isEmpty == false else { return }

        applyUsageRecords(cachedRecords)
        if warningMessage == nil, totalTokens > 0 {
            warningMessage = "已显示从 CSV 导入的用量记录"
        }
    }

    // MARK: - Cache

    /// 从本地缓存恢复数据（App 冷启动时调用）
    private func loadCachedData() {
        guard let cached = LocalCache.shared.loadDashboard() else { return }

        isAccountAvailable = cached.isAccountAvailable
        totalBalance = cached.totalBalance
        grantedBalance = cached.grantedBalance
        toppedUpBalance = cached.toppedUpBalance
        currentDayCost = cached.currentDayCost
        currentMonthCost = cached.currentMonthCost

        flashUsage = cachedSummary(
            model: .flash,
            totalTokens: cached.flashTotalTokens,
            costInCents: cached.flashCostInCents
        )

        proUsage = cachedSummary(
            model: .pro,
            totalTokens: cached.proTotalTokens,
            costInCents: cached.proCostInCents
        )

        // 恢复 Date-keyed 字典
        var restored: [Date: Int] = [:]
        for (dateStr, tokens) in cached.dailyUsage {
            if let date = recordDay(from: dateStr) {
                restored[date] = tokens
            }
        }
        dailyUsage = restored

        lastUpdated = cached.lastUpdated
        loadImportedUsageIfAvailable()
    }

    /// 保存当前状态到本地缓存（每次成功刷新后调用）
    private func saveCache() {
        var dailyUsageStrings: [String: Int] = [:]
        for (date, tokens) in dailyUsage {
            dailyUsageStrings[cacheDateFormatter.string(from: date)] = tokens
        }

        let cache = DashboardCache(
            isAccountAvailable: isAccountAvailable,
            totalBalance: totalBalance,
            grantedBalance: grantedBalance,
            toppedUpBalance: toppedUpBalance,
            currentDayCost: currentDayCost,
            currentMonthCost: currentMonthCost,
            flashTotalTokens: flashUsage?.totalTokens ?? 0,
            flashCostInCents: flashUsage?.costInCents ?? 0,
            proTotalTokens: proUsage?.totalTokens ?? 0,
            proCostInCents: proUsage?.costInCents ?? 0,
            dailyUsage: dailyUsageStrings,
            lastUpdated: lastUpdated ?? Date()
        )

        LocalCache.shared.saveDashboard(cache)
    }

    private func summary(for records: [UsageRecord], model: DeepSeekModel) -> ModelUsageSummary? {
        guard records.isEmpty == false else { return nil }
        return ModelUsageSummary(
            model: model,
            totalTokens: records.reduce(0) { $0 + $1.totalTokens },
            costInCents: records.reduce(0) { $0 + $1.costInCents }
        )
    }

    private func cachedSummary(model: DeepSeekModel, totalTokens: Int, costInCents: Int) -> ModelUsageSummary? {
        guard totalTokens > 0 || costInCents > 0 else { return nil }
        return ModelUsageSummary(
            model: model,
            totalTokens: totalTokens,
            costInCents: costInCents
        )
    }

    private func computeCurrentMonthCost(from records: [UsageRecord]) -> Double {
        let calendar = Calendar.current
        let now = Date()
        let totalCents = records.reduce(0) { partial, record in
            guard let day = recordDay(from: record.date),
                  calendar.isDate(day, equalTo: now, toGranularity: .month),
                  calendar.isDate(day, equalTo: now, toGranularity: .year) else {
                return partial
            }
            return partial + record.costInCents
        }
        return Double(totalCents) / 100.0
    }

    private func computeCurrentDayCost(from records: [UsageRecord]) -> Double {
        let calendar = Calendar.current
        let now = Date()
        let totalCents = records.reduce(0) { partial, record in
            guard let day = recordDay(from: record.date),
                  calendar.isDate(day, inSameDayAs: now) else {
                return partial
            }
            return partial + record.costInCents
        }
        return Double(totalCents) / 100.0
    }

    private func buildModelDailyPoints(from values: [Date: (tokens: Int, hit: Int, miss: Int, output: Int, requests: Int)]) -> [ModelDailyUsagePoint] {
        values.keys.sorted().map { date in
            let metrics = values[date] ?? (0, 0, 0, 0, 0)
            return ModelDailyUsagePoint(
                date: date,
                label: chartDateFormatter.string(from: date),
                totalTokens: metrics.tokens,
                inputCacheHitTokens: metrics.hit,
                inputCacheMissTokens: metrics.miss,
                outputTokens: metrics.output,
                requestCount: metrics.requests
            )
        }
    }

    private func normalizedModelName(_ name: String) -> DeepSeekModel? {
        let normalized = name.lowercased()
        if normalized.contains("reasoner") || normalized.contains("pro") {
            return .pro
        }
        if normalized.contains("chat") || normalized.contains("flash") {
            return .flash
        }
        return nil
    }

    private func recordDay(from raw: String) -> Date? {
        guard let parsed = cacheDateFormatter.date(from: raw) else { return nil }
        return Calendar.current.startOfDay(for: parsed)
    }

    private var chartDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M/d"
        return formatter
    }

    private var cacheDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
