import Foundation

// MARK: - Local Cache
//
// UserDefaults 本地持久化，确保：
// 1. App 重启后显示上次的数据，避免白屏
// 2. 网络不可用时仍可查看历史
// 3. 缓存数据在首次刷新成功后被覆盖

final class LocalCache {

    static let shared = LocalCache()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let dashboard = "cached_dashboard"
        static let usageHistory = "cached_usage_history"
    }

    // MARK: - Dashboard Snapshot

    /// 缓存 Dashboard 状态快照
    func saveDashboard(_ dashboard: DashboardCache) {
        guard let data = try? encoder.encode(dashboard) else { return }
        defaults.set(data, forKey: Keys.dashboard)
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

    // MARK: - Usage History (最近 30 天明细)

    func saveUsageRecords(_ records: [UsageRecord]) {
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: Keys.usageHistory)
    }

    func loadUsageRecords() -> [UsageRecord] {
        guard let data = defaults.data(forKey: Keys.usageHistory) else { return [] }
        return (try? decoder.decode([UsageRecord].self, from: data)) ?? []
    }

    // MARK: - Clear

    func clearAll() {
        defaults.removeObject(forKey: Keys.dashboard)
        defaults.removeObject(forKey: Keys.usageHistory)
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
    let currentDayCost: Double
    let currentMonthCost: Double
    let flashTotalTokens: Int
    let flashCostInCents: Int
    let proTotalTokens: Int
    let proCostInCents: Int
    let dailyUsage: [String: Int]  // "2026-05-01" -> tokens
    let lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case isAccountAvailable
        case totalBalance
        case grantedBalance
        case toppedUpBalance
        case currentDayCost
        case currentMonthCost
        case flashTotalTokens
        case flashCostInCents
        case proTotalTokens
        case proCostInCents
        case dailyUsage
        case lastUpdated
    }

    init(
        isAccountAvailable: Bool,
        totalBalance: Double,
        grantedBalance: Double,
        toppedUpBalance: Double,
        currentDayCost: Double,
        currentMonthCost: Double,
        flashTotalTokens: Int,
        flashCostInCents: Int,
        proTotalTokens: Int,
        proCostInCents: Int,
        dailyUsage: [String: Int],
        lastUpdated: Date
    ) {
        self.isAccountAvailable = isAccountAvailable
        self.totalBalance = totalBalance
        self.grantedBalance = grantedBalance
        self.toppedUpBalance = toppedUpBalance
        self.currentDayCost = currentDayCost
        self.currentMonthCost = currentMonthCost
        self.flashTotalTokens = flashTotalTokens
        self.flashCostInCents = flashCostInCents
        self.proTotalTokens = proTotalTokens
        self.proCostInCents = proCostInCents
        self.dailyUsage = dailyUsage
        self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isAccountAvailable = try container.decode(Bool.self, forKey: .isAccountAvailable)
        totalBalance = try container.decode(Double.self, forKey: .totalBalance)
        grantedBalance = try container.decode(Double.self, forKey: .grantedBalance)
        toppedUpBalance = try container.decode(Double.self, forKey: .toppedUpBalance)
        currentDayCost = try container.decodeIfPresent(Double.self, forKey: .currentDayCost) ?? 0
        currentMonthCost = try container.decodeIfPresent(Double.self, forKey: .currentMonthCost) ?? 0
        flashTotalTokens = try container.decode(Int.self, forKey: .flashTotalTokens)
        flashCostInCents = try container.decode(Int.self, forKey: .flashCostInCents)
        proTotalTokens = try container.decode(Int.self, forKey: .proTotalTokens)
        proCostInCents = try container.decode(Int.self, forKey: .proCostInCents)
        dailyUsage = try container.decode([String: Int].self, forKey: .dailyUsage)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
    }
}
