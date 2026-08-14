import Foundation
import Combine
import Dispatch

enum UsageAutoImportResult {
    case noNewFile
    case success([String])
    case failure(String)
}

enum UsageDataState: Equatable {
    case idle
    case live
    case imported
    case importedWithNotice(String)
    case unavailable(String)
    case failure(String)

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    var failureMessage: String? {
        guard case .failure(let message) = self else { return nil }
        return message
    }

    var noticeMessage: String? {
        switch self {
        case .importedWithNotice(let message), .unavailable(let message):
            return message
        default:
            return nil
        }
    }
}

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

    /// 账户是否可用（余额 > 0）
    @Published private(set) var isAccountAvailable: Bool = false
    /// 总余额（元）
    @Published private(set) var totalBalance: Double = 0
    /// 赠送余额（元）
    @Published private(set) var grantedBalance: Double = 0
    /// 充值余额（元）
    @Published private(set) var toppedUpBalance: Double = 0
    /// 余额币种
    @Published private(set) var balanceCurrencyCode: String = "CNY"
    /// 用量费用币种
    @Published private(set) var usageCurrencyCode: String = "CNY"
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
    /// 用量数据当前来源与可用状态
    @Published private(set) var usageDataState: UsageDataState = .idle
    /// 余额 API 上次成功刷新时间
    @Published private(set) var balanceLastUpdated: Date?
    /// 用量文件上次成功导入时间
    @Published private(set) var usageLastUpdated: Date?
    /// 是否已配置 API Key
    @Published private(set) var hasAPIKey: Bool = false
    /// API Key 安全存储或迁移错误
    @Published private(set) var apiKeyStorageError: String?
    /// 面板驻留时间（秒）
    @Published var panelResidenceSeconds: TimeInterval = 10 {
        didSet {
            let normalized = Self.normalizedPanelResidence(panelResidenceSeconds)
            if normalized != panelResidenceSeconds {
                panelResidenceSeconds = normalized
                return
            }
            preferences.set(normalized, forKey: Self.panelResidenceKey)
        }
    }
    /// 是否启用系统原生 WidgetKit 小组件数据
    @Published var isNativeWidgetEnabled: Bool = true {
        didSet {
            cache.setNativeWidgetEnabled(isNativeWidgetEnabled)
        }
    }

    // MARK: - Configuration

    /// 自动刷新间隔（秒），默认 60 秒
    @Published var refreshInterval: TimeInterval = 60 {
        didSet {
            let normalized = Self.normalizedRefreshInterval(refreshInterval)
            if normalized != refreshInterval {
                refreshInterval = normalized
                return
            }
            preferences.set(normalized, forKey: Self.refreshIntervalKey)
            restartTimer()
        }
    }

    /// 用量查询回溯天数
    let usageLookbackDays = 7

    // MARK: - Private

    private static let panelResidenceKey = "panel_residence_seconds"
    private static let refreshIntervalKey = "balance_refresh_interval_seconds"

    private let service: DeepSeekServicing
    private let cache: LocalCache
    private let preferences: UserDefaults
    private var timer: Timer?
    private var importMonitors: [DirectoryChangeMonitor] = []
    private var importDebounceWorkItem: DispatchWorkItem?
    private var isRefreshing = false
    private var lastBalanceResponse: BalanceResponse?
    private var usageEndpointUnavailableForSession = false

    // MARK: - Init

    init(
        service: DeepSeekServicing = DeepSeekService.shared,
        cache: LocalCache = .shared,
        preferences: UserDefaults = .standard
    ) {
        self.service = service
        self.cache = cache
        self.preferences = preferences

        panelResidenceSeconds = Self.normalizedPanelResidence(
            preferences.double(forKey: Self.panelResidenceKey)
        )
        refreshInterval = Self.normalizedRefreshInterval(
            preferences.double(forKey: Self.refreshIntervalKey)
        )
        isNativeWidgetEnabled = cache.isNativeWidgetEnabled
        hasAPIKey = service.hasAPIKey
        apiKeyStorageError = service.apiKeyStorageWarning
        let cachedRecords = cache.loadUsageRecords()
        if cachedRecords.isEmpty {
            UsageAutoImportService.resetRememberedImport(defaults: preferences)
        } else if cachedRecords.contains(where: { $0.totalTokens > 0 }) &&
                    cachedRecords.allSatisfy({ $0.requestCount == 0 }) {
            UsageAutoImportService.resetRememberedImport(defaults: preferences)
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

    private static func normalizedRefreshInterval(_ value: TimeInterval) -> TimeInterval {
        let allowed: [TimeInterval] = [30, 60, 120, 300]
        return allowed.contains(value) ? value : 60
    }

    // MARK: - Refresh

    /// 手动刷新数据
    func refresh() async {
        // 防止并发刷新
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            isLoading = false
        }

        // 没有 API Key 时不请求
        guard hasAPIKey else {
            errorMessage = "请先配置 API Key"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let balanceResp = try await service.fetchBalance()

            // ── 更新余额 ──
            lastBalanceResponse = balanceResp
            applyBalanceResponse(balanceResp)
            balanceLastUpdated = Date()

            await refreshUsageIfSupported()

            // ── 持久化到本地缓存 ──
            saveCache()

        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

    }

    private func refreshUsageIfSupported() async {
        guard usageEndpointUnavailableForSession == false else { return }

        do {
            let usageResp = try await service.fetchRecentUsage(days: usageLookbackDays)
            let recentRange = UsageAutoImportService.expectedRecentExportRange(
                timeZone: usageTimeZone
            )
            let mergedRecords = cache.mergeUsageRecords(
                usageResp.data,
                replacing: recentRange,
                timeZone: usageTimeZone
            )
            applyUsageRecords(mergedRecords)
            usageDataState = .live
            usageLastUpdated = Date()
        } catch {
            handleUsageFailure(error)
        }
    }

    // MARK: - API Key

    /// 先验证候选 Key，成功后才写入钥匙串并更新余额。
    @discardableResult
    func validateAndSaveAPIKey(_ key: String) async throws -> BalanceResponse {
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.isEmpty == false else {
            throw APIKeyStorageError.emptyAPIKey
        }

        let balanceResponse = try await service.validateAPIKey(candidate)

        do {
            try service.saveAPIKey(candidate)
        } catch {
            apiKeyStorageError = error.localizedDescription
            throw error
        }

        hasAPIKey = true
        apiKeyStorageError = nil
        usageEndpointUnavailableForSession = false
        lastBalanceResponse = balanceResponse
        applyBalanceResponse(balanceResponse)
        balanceLastUpdated = Date()
        errorMessage = nil
        saveCache()
        return balanceResponse
    }

    /// 清除 API Key 并重置状态
    func clearAPIKey() throws {
        do {
            try service.clearAPIKey()
        } catch {
            apiKeyStorageError = error.localizedDescription
            throw error
        }
        hasAPIKey = false
        apiKeyStorageError = nil
        usageEndpointUnavailableForSession = false

        // 清除本地缓存
        cache.clearAll()
        UsageAutoImportService.resetRememberedImport(defaults: preferences)

        resetDisplayedData()
    }

    /// 清除业务缓存，但保留钥匙串中的 API Key 与用户设置。
    func clearCachedData() {
        cache.clearAll()
        UsageAutoImportService.resetRememberedImport(defaults: preferences)
        resetDisplayedData()
    }

    private func resetDisplayedData() {
        isAccountAvailable = false
        totalBalance = 0
        grantedBalance = 0
        toppedUpBalance = 0
        balanceCurrencyCode = "CNY"
        usageCurrencyCode = "CNY"
        currentDayCost = 0
        currentMonthCost = 0
        flashUsage = nil
        proUsage = nil
        dailyUsage = [:]
        flashDailyUsage = []
        proDailyUsage = []
        balanceLastUpdated = nil
        usageLastUpdated = nil
        errorMessage = nil
        usageDataState = .idle
        lastBalanceResponse = nil
    }

    @discardableResult
    func importUsageExport(from url: URL) throws -> [String] {
        let candidate = try UsageAutoImportService.prepareImportCandidate(from: url)
        return try importUsageCandidate(candidate)
    }

    @discardableResult
    func importAutomaticUsageExport(_ event: UsageExportDownloadEvent) -> UsageAutoImportResult {
        var candidate: UsageAutoImportService.ImportCandidate?
        do {
            let fingerprint = try UsageAutoImportService.importFingerprint(for: event.fileURL)
            guard UsageAutoImportService.hasImported(
                fingerprint,
                defaults: preferences
            ) == false else {
                return .noNewFile
            }
            let prepared = try UsageAutoImportService.prepareImportCandidate(from: event.fileURL)
            candidate = prepared
            let fileNames = try importUsageCandidate(
                prepared,
                automaticReferenceDate: event.referenceDate
            )
            try? UsageAutoImportService.cleanupImportedSources(keeping: event.fileURL)
            UsageExportAutomationService.shared.reportImportSuccess(fileNames: fileNames)
            return .success(fileNames)
        } catch {
            let sourceName = candidate?.sourceName ?? event.fileURL.lastPathComponent
            let retainedFile = try? UsageAutoImportService.quarantineFailedImport(event.fileURL)
            let retainedSuffix = retainedFile == nil ? "" : "，文件已保留到 failed 目录"
            let message = "自动导入 \(sourceName) 失败：\(error.localizedDescription)\(retainedSuffix)"
            usageDataState = .failure(message)
            UsageExportAutomationService.shared.reportImportFailure(error.localizedDescription)
            return .failure(message)
        }
    }

    private func importUsageCandidate(
        _ candidate: UsageAutoImportService.ImportCandidate,
        automaticReferenceDate: Date? = nil
    ) throws -> [String] {
        let result = try UsageCSVImporter.importResult(
            from: candidate.preparedAmountCSVURL,
            costURL: candidate.preparedCostCSVURL,
            defaultCurrencyCode: balanceCurrencyCode
        )
        let importTimeZone = result.timeZone ?? usageTimeZone
        let resolvedRange = try UsageAutoImportService.resolvedExportDateRange(
            candidate.exportDateRange,
            records: result.records,
            fileNameEndDateIsInclusive: result.fileNameEndDateIsInclusive
        )
        if let automaticReferenceDate {
            try UsageAutoImportService.validateAutomaticExport(
                candidate,
                exportDateRange: resolvedRange,
                referenceDate: automaticReferenceDate,
                timeZone: importTimeZone
            )
        }
        try applyImportedUsage(result, replacing: resolvedRange)
        UsageAutoImportService.markImported(candidate.fingerprint, defaults: preferences)
        return candidate.selectedCSVNames
    }

    private func applyImportedUsage(
        _ result: UsageCSVImportResult,
        replacing range: UsageAutoImportService.ExportDateRange?
    ) throws {
        try UsageAutoImportService.validateRecords(result.records, within: range)
        let importTimeZone = result.timeZone ?? usageTimeZone
        let mergedRecords = cache.mergeUsageRecords(
            result.records,
            replacing: range,
            timeZone: importTimeZone
        )
        if let secondsFromGMT = result.timeZoneSecondsFromGMT {
            cache.saveUsageTimeZone(secondsFromGMT: secondsFromGMT)
        }
        applyUsageRecords(mergedRecords)
        usageDataState = cache.needsCurrentMonthBaseline(timeZone: importTimeZone)
            ? .importedWithNotice("近 7 日用量已更新，本月历史仍需同步完整的本月 ZIP")
            : .imported
        usageLastUpdated = Date()
        saveCache()
    }

    @discardableResult
    func autoImportUsageIfNeeded() -> UsageAutoImportResult {
        var activeCandidate: UsageAutoImportService.ImportCandidate?
        do {
            guard let candidate = try UsageAutoImportService.nextImportCandidate(
                defaults: preferences
            ) else {
                return .noNewFile
            }
            activeCandidate = candidate
            let fileNames = try importUsageCandidate(candidate)
            try? UsageAutoImportService.cleanupImportedSources(keeping: candidate.sourceURL)
            UsageExportAutomationService.shared.reportImportSuccess(fileNames: fileNames)
            return .success(fileNames)
        } catch {
            let message: String
            if let candidate = activeCandidate {
                let selectedNames = candidate.selectedCSVNames.joined(separator: " + ")
                let retainedFile = try? UsageAutoImportService.quarantineFailedImport(candidate.sourceURL)
                let retainedSuffix = retainedFile == nil ? "" : "，文件已保留到 failed 目录"
                message = "自动导入 \(candidate.sourceName) -> \(selectedNames) 失败：\(error.localizedDescription)\(retainedSuffix)"
            } else {
                message = "自动导入用量失败：\(error.localizedDescription)"
            }
            usageDataState = .failure(message)
            UsageExportAutomationService.shared.reportImportFailure(error.localizedDescription)
            return .failure(message)
        }
    }

    // MARK: - Computed

    /// 总 Token 消耗（所有模型合计）
    var totalTokens: Int {
        (flashUsage?.totalTokens ?? 0) + (proUsage?.totalTokens ?? 0)
    }

    var usageTimeZone: TimeZone {
        cache.usageTimeZone
    }

    var apiKey: String? {
        service.apiKey
    }

    var lastUpdated: Date? {
        [balanceLastUpdated, usageLastUpdated].compactMap { $0 }.max()
    }

    /// DeepSeek 公开 API 当前是否不支持用量查询
    var isUsageUnavailable: Bool {
        usageDataState.isUnavailable
    }

    var usageFailureMessage: String? {
        usageDataState.failureMessage
    }

    var usageNoticeMessage: String? {
        usageDataState.noticeMessage
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
        let calendar = UsageTime.calendar(in: usageTimeZone)
        let today = calendar.startOfDay(for: Date())
        let dayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.timeZone = usageTimeZone
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
        let flashRecords = records.filter { normalizedModelName($0.modelName) == .flash }
        let proRecords   = records.filter { normalizedModelName($0.modelName) == .pro }

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
        let recentRange = UsageAutoImportService.expectedRecentExportRange(
            timeZone: usageTimeZone
        )
        let recentRecords = records.filter { recentRange.contains($0.date) }
        let currencyRecords = recentRecords.isEmpty ? records : recentRecords
        usageCurrencyCode = preferredUsageCurrency(from: currencyRecords)
        if let lastBalanceResponse {
            applyBalanceResponse(lastBalanceResponse)
        }
        aggregateUsage(recentRecords)
        buildDailyUsage(from: recentRecords)
        currentDayCost = computeCurrentDayCost(from: records)
        currentMonthCost = computeCurrentMonthCost(from: records)
    }

    private func restoreImportedUsageIfAvailable(unavailableMessage: String) -> Bool {
        let cachedRecords = cache.loadUsageRecords()
        guard cachedRecords.isEmpty == false else { return false }

        applyUsageRecords(cachedRecords)
        usageDataState = .importedWithNotice(
            "\(unavailableMessage)，已显示导入的 CSV 记录"
        )
        return true
    }

    private func handleUsageFailure(_ error: Error) {
        if let apiError = error as? APIError,
           case .usageEndpointUnavailable = apiError {
            usageEndpointUnavailableForSession = true
            let message = apiError.errorDescription ?? "实时用量不可用"
            if restoreImportedUsageIfAvailable(unavailableMessage: message) == false {
                clearUsageData()
                usageDataState = .unavailable(message)
            }
            return
        }

        if let apiError = error as? APIError {
            if restoreImportedUsageIfAvailable(unavailableMessage: "实时用量同步失败") == false {
                usageDataState = .failure("用量同步失败：\(apiError.errorDescription ?? "未知错误")")
            }
        } else {
            if restoreImportedUsageIfAvailable(unavailableMessage: "实时用量同步失败") == false {
                usageDataState = .failure("用量同步失败：\(error.localizedDescription)")
            }
        }
    }

    func loadImportedUsageIfAvailable() {
        let cachedRecords = cache.loadUsageRecords()
        guard cachedRecords.isEmpty == false else { return }

        applyUsageRecords(cachedRecords)
        if totalTokens > 0 {
            usageDataState = .imported
        }
    }

    // MARK: - Cache

    /// 从本地缓存恢复数据（App 冷启动时调用）
    private func loadCachedData() {
        guard let cached = cache.loadDashboard() else { return }

        isAccountAvailable = cached.isAccountAvailable
        totalBalance = cached.totalBalance
        grantedBalance = cached.grantedBalance
        toppedUpBalance = cached.toppedUpBalance
        balanceCurrencyCode = cached.balanceCurrencyCode
        usageCurrencyCode = cached.usageCurrencyCode
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

        balanceLastUpdated = cached.balanceLastUpdated
        usageLastUpdated = cached.usageLastUpdated
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
            balanceCurrencyCode: balanceCurrencyCode,
            usageCurrencyCode: usageCurrencyCode,
            currentDayCost: currentDayCost,
            currentMonthCost: currentMonthCost,
            flashTotalTokens: flashUsage?.totalTokens ?? 0,
            flashCostInCents: flashUsage?.costInCents ?? 0,
            proTotalTokens: proUsage?.totalTokens ?? 0,
            proCostInCents: proUsage?.costInCents ?? 0,
            dailyUsage: dailyUsageStrings,
            balanceLastUpdated: balanceLastUpdated,
            usageLastUpdated: usageLastUpdated,
            lastUpdated: lastUpdated ?? Date()
        )

        self.cache.saveDashboard(cache)
    }

    private func summary(for records: [UsageRecord], model: DeepSeekModel) -> ModelUsageSummary? {
        guard records.isEmpty == false else { return nil }
        return ModelUsageSummary(
            model: model,
            totalTokens: records.reduce(0) { $0 + $1.totalTokens },
            costAmount: records.reduce(Decimal.zero) {
                $0 + $1.costAmount(for: usageCurrencyCode)
            },
            currencyCode: usageCurrencyCode
        )
    }

    private func cachedSummary(model: DeepSeekModel, totalTokens: Int, costInCents: Int) -> ModelUsageSummary? {
        guard totalTokens > 0 || costInCents > 0 else { return nil }
        return ModelUsageSummary(
            model: model,
            totalTokens: totalTokens,
            costAmount: decimalAmount(fromCents: costInCents),
            currencyCode: usageCurrencyCode
        )
    }

    private func computeCurrentMonthCost(from records: [UsageRecord]) -> Double {
        let now = Date()
        let totalAmount = records.reduce(Decimal.zero) { partial, record in
            guard UsageTime.isSameMonth(
                record.date,
                as: now,
                timeZone: usageTimeZone
            ) else {
                return partial
            }
            return partial + record.costAmount(for: usageCurrencyCode)
        }
        return NSDecimalNumber(decimal: totalAmount).doubleValue
    }

    private func computeCurrentDayCost(from records: [UsageRecord]) -> Double {
        let now = Date()
        let totalAmount = records.reduce(Decimal.zero) { partial, record in
            guard UsageTime.isSameDay(
                record.date,
                as: now,
                timeZone: usageTimeZone
            ) else {
                return partial
            }
            return partial + record.costAmount(for: usageCurrencyCode)
        }
        return NSDecimalNumber(decimal: totalAmount).doubleValue
    }

    private func preferredUsageCurrency(from records: [UsageRecord]) -> String {
        var totals: [String: Decimal] = [:]
        for record in records {
            for (currency, amount) in record.costByCurrency {
                totals[normalizedCurrencyCode(currency), default: .zero] += amount
            }
        }

        let nonZeroCurrencies = totals
            .filter { $0.value != .zero }
            .map(\.key)
        if nonZeroCurrencies.count == 1, let onlyCurrency = nonZeroCurrencies.first {
            return onlyCurrency
        }
        if nonZeroCurrencies.contains(balanceCurrencyCode) {
            return balanceCurrencyCode
        }
        if let firstNonZero = nonZeroCurrencies.sorted().first {
            return firstNonZero
        }
        if totals.keys.contains(balanceCurrencyCode) {
            return balanceCurrencyCode
        }
        return totals.keys.sorted().first ?? balanceCurrencyCode
    }

    private func applyBalanceResponse(_ response: BalanceResponse) {
        guard let info = response.preferredBalanceInfo(matching: usageCurrencyCode) else { return }
        isAccountAvailable = response.isAvailable
        totalBalance = Double(info.totalBalance) ?? 0
        grantedBalance = Double(info.grantedBalance) ?? 0
        toppedUpBalance = Double(info.toppedUpBalance) ?? 0
        balanceCurrencyCode = normalizedCurrencyCode(info.currency)
    }

    private func buildModelDailyPoints(from values: [Date: (tokens: Int, hit: Int, miss: Int, output: Int, requests: Int)]) -> [ModelDailyUsagePoint] {
        values.keys.sorted().map { date in
            let normalizedDate = UsageTime.calendar(in: usageTimeZone).startOfDay(for: date)
            let metrics = values[date] ?? (0, 0, 0, 0, 0)
            return ModelDailyUsagePoint(
                date: normalizedDate,
                label: chartDateFormatter.string(from: normalizedDate),
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
        UsageTime.day(from: raw, timeZone: usageTimeZone)
    }

    private var chartDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = usageTimeZone
        formatter.dateFormat = "M/d"
        return formatter
    }

    private var cacheDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = usageTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
