import WidgetKit

// MARK: - Shared Data Model

struct WidgetSnapshot: Codable {
    let isWidgetEnabled: Bool?
    let totalBalance: Double
    let isAccountAvailable: Bool
    let currentDayCost: Double
    let currentMonthCost: Double
    let flashTotalTokens: Int
    let flashCostInCents: Int
    let proTotalTokens: Int
    let proCostInCents: Int
    let lastUpdated: Date
}

// MARK: - Timeline Entry

struct WidgetEntry: TimelineEntry {
    let date: Date
    let isWidgetEnabled: Bool
    let balance: Double
    let isAvailable: Bool
    let dayCost: Double
    let monthCost: Double
    let flashTokens: Int
    let flashCostCents: Int
    let proTokens: Int
    let proCostCents: Int
    let lastUpdated: Date
    let hasData: Bool

    static let placeholder = WidgetEntry(
        date: Date(),
        isWidgetEnabled: true,
        balance: 0,
        isAvailable: false,
        dayCost: 0,
        monthCost: 0,
        flashTokens: 0,
        flashCostCents: 0,
        proTokens: 0,
        proCostCents: 0,
        lastUpdated: Date(),
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
                dayCost: 0,
                monthCost: 0,
                flashTokens: 0,
                flashCostCents: 0,
                proTokens: 0,
                proCostCents: 0,
                lastUpdated: Date(),
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
            dayCost: s.currentDayCost,
            monthCost: s.currentMonthCost,
            flashTokens: s.flashTotalTokens,
            flashCostCents: s.flashCostInCents,
            proTokens: s.proTotalTokens,
            proCostCents: s.proCostInCents,
            lastUpdated: s.lastUpdated,
            hasData: true
        )
    }
}
