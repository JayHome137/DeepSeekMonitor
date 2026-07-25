import WidgetKit

// MARK: - Shared Data Model

struct WidgetSnapshot: Decodable {
    let isWidgetEnabled: Bool?
    let totalBalance: Double
    let isAccountAvailable: Bool
    let balanceCurrencyCode: String
    let usageCurrencyCode: String
    let currentDayCost: Double
    let currentMonthCost: Double
    let flashTotalTokens: Int
    let flashCostInCents: Int
    let proTotalTokens: Int
    let proCostInCents: Int
    let balanceUpdatedAt: Date
    let usageUpdatedAt: Date
    let usageTimeZoneOffsetSeconds: Int
    let lastUpdated: Date

    private enum CodingKeys: String, CodingKey {
        case isWidgetEnabled
        case totalBalance
        case isAccountAvailable
        case balanceCurrencyCode
        case usageCurrencyCode
        case currentDayCost
        case currentMonthCost
        case flashTotalTokens
        case flashCostInCents
        case proTotalTokens
        case proCostInCents
        case balanceUpdatedAt
        case usageUpdatedAt
        case usageTimeZoneOffsetSeconds
        case lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isWidgetEnabled = try container.decodeIfPresent(Bool.self, forKey: .isWidgetEnabled)
        totalBalance = try container.decode(Double.self, forKey: .totalBalance)
        isAccountAvailable = try container.decode(Bool.self, forKey: .isAccountAvailable)
        balanceCurrencyCode = try container.decodeIfPresent(String.self, forKey: .balanceCurrencyCode) ?? "CNY"
        usageCurrencyCode = try container.decodeIfPresent(String.self, forKey: .usageCurrencyCode) ?? balanceCurrencyCode
        currentDayCost = try container.decode(Double.self, forKey: .currentDayCost)
        currentMonthCost = try container.decode(Double.self, forKey: .currentMonthCost)
        flashTotalTokens = try container.decode(Int.self, forKey: .flashTotalTokens)
        flashCostInCents = try container.decode(Int.self, forKey: .flashCostInCents)
        proTotalTokens = try container.decode(Int.self, forKey: .proTotalTokens)
        proCostInCents = try container.decode(Int.self, forKey: .proCostInCents)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        balanceUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .balanceUpdatedAt) ?? lastUpdated
        usageUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .usageUpdatedAt) ?? lastUpdated
        usageTimeZoneOffsetSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .usageTimeZoneOffsetSeconds
        ) ?? 0
    }
}

// MARK: - Timeline Entry

struct WidgetEntry: TimelineEntry {
    let date: Date
    let isWidgetEnabled: Bool
    let balance: Double
    let isAvailable: Bool
    let balanceCurrencyCode: String
    let usageCurrencyCode: String
    let dayCost: Double
    let monthCost: Double
    let flashTokens: Int
    let flashCostCents: Int
    let proTokens: Int
    let proCostCents: Int
    let usageUpdatedAt: Date
    let usageTimeZoneOffsetSeconds: Int
    let hasData: Bool

    static let placeholder = WidgetEntry(
        date: Date(),
        isWidgetEnabled: true,
        balance: 0,
        isAvailable: false,
        balanceCurrencyCode: "CNY",
        usageCurrencyCode: "CNY",
        dayCost: 0,
        monthCost: 0,
        flashTokens: 0,
        flashCostCents: 0,
        proTokens: 0,
        proCostCents: 0,
        usageUpdatedAt: Date(),
        usageTimeZoneOffsetSeconds: 0,
        hasData: false
    )
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {

    private func loadSnapshot() -> WidgetSnapshot? {
        guard let sharedDefaults = UserDefaults(suiteName: "N5YV5FV235.group.com.deepseek.monitor"),
              let data = sharedDefaults.data(forKey: "widget_snapshot") else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    private func isWidgetEnabled() -> Bool {
        guard let sharedDefaults = UserDefaults(suiteName: "N5YV5FV235.group.com.deepseek.monitor") else {
            return true
        }
        return sharedDefaults.object(forKey: "native_widget_enabled") as? Bool ?? true
    }

    func placeholder(in context: Context) -> WidgetEntry {
        let snapshot = loadSnapshot()
        return entryFromSnapshot(snapshot, isEnabled: snapshot?.isWidgetEnabled ?? isWidgetEnabled())
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        let snapshot = loadSnapshot()
        let entry = entryFromSnapshot(snapshot, isEnabled: snapshot?.isWidgetEnabled ?? isWidgetEnabled())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let entry = entryFromSnapshot(snapshot, isEnabled: snapshot?.isWidgetEnabled ?? isWidgetEnabled())
        // Policy: app controls refresh via WidgetCenter.reloadAllTimelines()
        // Fallback: auto-refresh after 1 hour
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    private func entryFromSnapshot(_ snapshot: WidgetSnapshot?, isEnabled: Bool) -> WidgetEntry {
        guard isEnabled else {
            return WidgetEntry(
                date: Date(),
                isWidgetEnabled: false,
                balance: 0,
                isAvailable: false,
                balanceCurrencyCode: "CNY",
                usageCurrencyCode: "CNY",
                dayCost: 0,
                monthCost: 0,
                flashTokens: 0,
                flashCostCents: 0,
                proTokens: 0,
                proCostCents: 0,
                usageUpdatedAt: Date(),
                usageTimeZoneOffsetSeconds: 0,
                hasData: false
            )
        }

        guard let s = snapshot else {
            return WidgetEntry.placeholder
        }
        return WidgetEntry(
            date: Date(),
            isWidgetEnabled: true,
            balance: s.totalBalance,
            isAvailable: s.isAccountAvailable,
            balanceCurrencyCode: s.balanceCurrencyCode,
            usageCurrencyCode: s.usageCurrencyCode,
            dayCost: s.currentDayCost,
            monthCost: s.currentMonthCost,
            flashTokens: s.flashTotalTokens,
            flashCostCents: s.flashCostInCents,
            proTokens: s.proTotalTokens,
            proCostCents: s.proCostInCents,
            usageUpdatedAt: s.usageUpdatedAt,
            usageTimeZoneOffsetSeconds: s.usageTimeZoneOffsetSeconds,
            hasData: true
        )
    }
}
