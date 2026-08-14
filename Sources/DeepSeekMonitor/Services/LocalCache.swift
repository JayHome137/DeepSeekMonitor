import Foundation
import WidgetKit

// MARK: - Local Cache
//
// UserDefaults 本地持久化，确保：
// 1. App 重启后显示上次的数据，避免白屏
// 2. 网络不可用时仍可查看历史
// 3. 缓存数据在首次刷新成功后被覆盖

final class LocalCache {

    static let shared = LocalCache()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Keys {
        static let dashboard = "cached_dashboard"
        static let usageHistory = "cached_usage_history"
        static let usageHistorySchemaVersion = "cached_usage_history_schema_version"
        static let usageBaselineMonth = "cached_usage_baseline_month"
        static let usageTimeZoneSecondsFromGMT = "cached_usage_timezone_seconds_from_gmt"
        static let nativeWidgetEnabled = "native_widget_enabled"
        static let widgetSnapshot = "widget_snapshot"
    }

    private static let currentUsageHistorySchemaVersion = 3

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: "N5YV5FV235.group.com.deepseek.monitor")
    }

    // MARK: - Dashboard Snapshot

    /// 缓存 Dashboard 状态快照
    func saveDashboard(_ dashboard: DashboardCache) {
        guard let data = try? encoder.encode(dashboard) else { return }
        defaults.set(data, forKey: Keys.dashboard)

        // 同步写入 App Group 供 Widget Extension 消费
        saveWidgetSnapshot(from: dashboard)
    }

    /// 读取缓存的 Dashboard 快照
    func loadDashboard() -> DashboardCache? {
        guard let data = defaults.data(forKey: Keys.dashboard) else { return nil }
        return try? decoder.decode(DashboardCache.self, from: data)
    }

    /// 是否有缓存
    var hasCachedDashboard: Bool {
        defaults.data(forKey: Keys.dashboard) != nil
    }

    // MARK: - Usage History (本月明细 + 最近 7 天)

    func saveUsageRecords(_ records: [UsageRecord]) {
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: Keys.usageHistory)
    }

    @discardableResult
    func mergeUsageRecords(
        _ records: [UsageRecord],
        replacing range: UsageAutoImportService.ExportDateRange? = nil,
        referenceDate: Date = Date(),
        timeZone: TimeZone? = nil
    ) -> [UsageRecord] {
        let timeZone = timeZone ?? usageTimeZone
        let completesCurrentMonthBaseline = range.map {
            Self.rangeCoversCurrentMonth(
                $0,
                referenceDate: referenceDate,
                timeZone: timeZone
            )
        } ?? false
        let shouldDiscardLegacyHistory = needsUsageHistoryMigration && completesCurrentMonthBaseline
        let merged = Self.mergedUsageRecords(
            existing: shouldDiscardLegacyHistory ? [] : loadUsageRecords(),
            incoming: records,
            replacing: range,
            referenceDate: referenceDate,
            timeZone: timeZone
        )
        saveUsageRecords(merged)
        if completesCurrentMonthBaseline {
            markCurrentMonthBaseline(referenceDate: referenceDate, timeZone: timeZone)
        }
        return merged
    }

    static func mergedUsageRecords(
        existing: [UsageRecord],
        incoming: [UsageRecord],
        replacing range: UsageAutoImportService.ExportDateRange?,
        referenceDate: Date,
        timeZone: TimeZone = UsageTime.defaultTimeZone
    ) -> [UsageRecord] {
        let retainedExisting: [UsageRecord]
        if let range {
            retainedExisting = existing.filter { range.contains($0.date) == false }
        } else {
            let incomingKeys = Set(incoming.map(recordKey))
            retainedExisting = existing.filter { incomingKeys.contains(recordKey($0)) == false }
        }

        let calendar = UsageTime.calendar(in: timeZone)
        let today = calendar.startOfDay(for: referenceDate)
        let recentStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let retentionStart = min(recentStart, monthStart)
        let retentionStartText = UsageTime.formatter(
            "yyyy-MM-dd",
            timeZone: timeZone
        ).string(from: retentionStart)

        var byKey: [String: UsageRecord] = [:]
        for record in retainedExisting + incoming where record.date >= retentionStartText {
            byKey[recordKey(record)] = record
        }

        return byKey.values.sorted {
            if $0.date == $1.date {
                return $0.modelName < $1.modelName
            }
            return $0.date < $1.date
        }
    }

    private static func recordKey(_ record: UsageRecord) -> String {
        "\(record.date)|\(record.modelName.lowercased())"
    }

    static func rangeCoversCurrentMonth(
        _ range: UsageAutoImportService.ExportDateRange,
        referenceDate: Date,
        timeZone: TimeZone = UsageTime.defaultTimeZone
    ) -> Bool {
        let expected = UsageAutoImportService.expectedCurrentMonthExportRange(
            referenceDate: referenceDate,
            timeZone: timeZone
        )
        let calendar = UsageTime.calendar(in: timeZone)
        let today = calendar.startOfDay(for: referenceDate)
        let todayText = UsageTime.formatter(
            "yyyy-MM-dd",
            timeZone: timeZone
        ).string(from: today)
        return range.startDate <= expected.startDate &&
            range.endDateExclusive >= todayText &&
            range.endDateExclusive <= expected.endDateExclusive
    }

    func needsCurrentMonthBaseline(
        referenceDate: Date = Date(),
        timeZone: TimeZone? = nil
    ) -> Bool {
        guard needsUsageHistoryMigration == false else { return true }
        let timeZone = timeZone ?? usageTimeZone
        let month = UsageTime.formatter(
            "yyyy-MM",
            timeZone: timeZone
        ).string(from: referenceDate)
        return defaults.string(forKey: Keys.usageBaselineMonth) != month
    }

    private var needsUsageHistoryMigration: Bool {
        defaults.integer(forKey: Keys.usageHistorySchemaVersion) < Self.currentUsageHistorySchemaVersion
    }

    private func markCurrentMonthBaseline(referenceDate: Date, timeZone: TimeZone) {
        defaults.set(Self.currentUsageHistorySchemaVersion, forKey: Keys.usageHistorySchemaVersion)
        defaults.set(
            UsageTime.formatter("yyyy-MM", timeZone: timeZone).string(from: referenceDate),
            forKey: Keys.usageBaselineMonth
        )
    }

    var usageTimeZone: TimeZone {
        let secondsFromGMT = defaults.object(forKey: Keys.usageTimeZoneSecondsFromGMT) == nil
            ? 0
            : defaults.integer(forKey: Keys.usageTimeZoneSecondsFromGMT)
        return TimeZone(secondsFromGMT: secondsFromGMT) ?? UsageTime.defaultTimeZone
    }

    func saveUsageTimeZone(secondsFromGMT: Int) {
        guard TimeZone(secondsFromGMT: secondsFromGMT) != nil else { return }
        defaults.set(secondsFromGMT, forKey: Keys.usageTimeZoneSecondsFromGMT)
    }

    func loadUsageRecords() -> [UsageRecord] {
        guard let data = defaults.data(forKey: Keys.usageHistory) else { return [] }
        return (try? decoder.decode([UsageRecord].self, from: data)) ?? []
    }

    // MARK: - Clear

    func clearAll() {
        defaults.removeObject(forKey: Keys.dashboard)
        defaults.removeObject(forKey: Keys.usageHistory)
        defaults.removeObject(forKey: Keys.usageHistorySchemaVersion)
        defaults.removeObject(forKey: Keys.usageBaselineMonth)
        defaults.removeObject(forKey: Keys.usageTimeZoneSecondsFromGMT)
    }

    // MARK: - Native Widget

    var isNativeWidgetEnabled: Bool {
        guard let sharedDefaults else { return true }
        return sharedDefaults.object(forKey: Keys.nativeWidgetEnabled) as? Bool ?? true
    }

    func setNativeWidgetEnabled(_ isEnabled: Bool) {
        sharedDefaults?.set(isEnabled, forKey: Keys.nativeWidgetEnabled)
        sharedDefaults?.synchronize()

        if let cachedDashboard = loadDashboard() {
            saveWidgetSnapshot(from: cachedDashboard)
        } else {
            WidgetCenter.shared.reloadTimelines(ofKind: "com.deepseek.monitor.widget")
        }
    }

    // MARK: - Widget Snapshot

    /// 写入 Widget 快照到 App Group 共享容器
    private func saveWidgetSnapshot(from dashboard: DashboardCache) {
        let snapshot = WidgetSnapshot(
            isWidgetEnabled: isNativeWidgetEnabled,
            totalBalance: dashboard.totalBalance,
            isAccountAvailable: dashboard.isAccountAvailable,
            balanceCurrencyCode: dashboard.balanceCurrencyCode,
            usageCurrencyCode: dashboard.usageCurrencyCode,
            currentDayCost: dashboard.currentDayCost,
            currentMonthCost: dashboard.currentMonthCost,
            flashTotalTokens: dashboard.flashTotalTokens,
            flashCostInCents: dashboard.flashCostInCents,
            proTotalTokens: dashboard.proTotalTokens,
            proCostInCents: dashboard.proCostInCents,
            balanceUpdatedAt: dashboard.balanceLastUpdated ?? dashboard.lastUpdated,
            usageUpdatedAt: dashboard.usageLastUpdated ?? dashboard.lastUpdated,
            lastUpdated: dashboard.lastUpdated
        )

        guard let sharedDefaults,
              let snapshotData = try? encoder.encode(snapshot) else { return }

        sharedDefaults.set(snapshotData, forKey: Keys.widgetSnapshot)
        sharedDefaults.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "com.deepseek.monitor.widget")
    }
}

// MARK: - Cache Model
//
// 轻量 Codable 结构，只存 UI 需要的最小字段

struct DashboardCache: Codable {
    let isAccountAvailable: Bool
    let totalBalance: Double
    let grantedBalance: Double
    let toppedUpBalance: Double
    let balanceCurrencyCode: String
    let usageCurrencyCode: String
    let currentDayCost: Double
    let currentMonthCost: Double
    let flashTotalTokens: Int
    let flashCostInCents: Int
    let proTotalTokens: Int
    let proCostInCents: Int
    let dailyUsage: [String: Int]  // "2026-05-01" -> tokens
    let balanceLastUpdated: Date?
    let usageLastUpdated: Date?
    let lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case isAccountAvailable
        case totalBalance
        case grantedBalance
        case toppedUpBalance
        case balanceCurrencyCode
        case usageCurrencyCode
        case currentDayCost
        case currentMonthCost
        case flashTotalTokens
        case flashCostInCents
        case proTotalTokens
        case proCostInCents
        case dailyUsage
        case balanceLastUpdated
        case usageLastUpdated
        case lastUpdated
    }

    init(
        isAccountAvailable: Bool,
        totalBalance: Double,
        grantedBalance: Double,
        toppedUpBalance: Double,
        balanceCurrencyCode: String,
        usageCurrencyCode: String,
        currentDayCost: Double,
        currentMonthCost: Double,
        flashTotalTokens: Int,
        flashCostInCents: Int,
        proTotalTokens: Int,
        proCostInCents: Int,
        dailyUsage: [String: Int],
        balanceLastUpdated: Date?,
        usageLastUpdated: Date?,
        lastUpdated: Date
    ) {
        self.isAccountAvailable = isAccountAvailable
        self.totalBalance = totalBalance
        self.grantedBalance = grantedBalance
        self.toppedUpBalance = toppedUpBalance
        self.balanceCurrencyCode = normalizedCurrencyCode(balanceCurrencyCode)
        self.usageCurrencyCode = normalizedCurrencyCode(usageCurrencyCode)
        self.currentDayCost = currentDayCost
        self.currentMonthCost = currentMonthCost
        self.flashTotalTokens = flashTotalTokens
        self.flashCostInCents = flashCostInCents
        self.proTotalTokens = proTotalTokens
        self.proCostInCents = proCostInCents
        self.dailyUsage = dailyUsage
        self.balanceLastUpdated = balanceLastUpdated
        self.usageLastUpdated = usageLastUpdated
        self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isAccountAvailable = try container.decode(Bool.self, forKey: .isAccountAvailable)
        totalBalance = try container.decode(Double.self, forKey: .totalBalance)
        grantedBalance = try container.decode(Double.self, forKey: .grantedBalance)
        toppedUpBalance = try container.decode(Double.self, forKey: .toppedUpBalance)
        balanceCurrencyCode = normalizedCurrencyCode(
            try container.decodeIfPresent(String.self, forKey: .balanceCurrencyCode) ?? "CNY"
        )
        usageCurrencyCode = normalizedCurrencyCode(
            try container.decodeIfPresent(String.self, forKey: .usageCurrencyCode) ?? balanceCurrencyCode
        )
        currentDayCost = try container.decodeIfPresent(Double.self, forKey: .currentDayCost) ?? 0
        currentMonthCost = try container.decodeIfPresent(Double.self, forKey: .currentMonthCost) ?? 0
        flashTotalTokens = try container.decode(Int.self, forKey: .flashTotalTokens)
        flashCostInCents = try container.decode(Int.self, forKey: .flashCostInCents)
        proTotalTokens = try container.decode(Int.self, forKey: .proTotalTokens)
        proCostInCents = try container.decode(Int.self, forKey: .proCostInCents)
        dailyUsage = try container.decode([String: Int].self, forKey: .dailyUsage)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        balanceLastUpdated = try container.decodeIfPresent(Date.self, forKey: .balanceLastUpdated) ?? lastUpdated
        usageLastUpdated = try container.decodeIfPresent(Date.self, forKey: .usageLastUpdated) ?? lastUpdated
    }
}
