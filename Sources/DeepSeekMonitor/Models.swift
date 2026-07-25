import Foundation

struct UsageTimeZoneOption: Identifiable, Hashable {
    let id: String
    let title: String
}

enum UsageTime {
    static let systemSelection = "system"

    private static let fixedOffsetPrefix = "offset:"
    private static let configuredSelectionKey = "usage_time_zone_selection"
    private static let importedOffsetKey = "usage_import_time_zone_offset_seconds"

    static var availableTimeZoneOptions: [UsageTimeZoneOption] {
        let systemOffset = TimeZone.current.secondsFromGMT(for: Date())
        let system = UsageTimeZoneOption(
            id: systemSelection,
            title: "跟随系统（\(offsetLabel(seconds: systemOffset))）"
        )
        let fixed = (-12...14).map { hour in
            let seconds = hour * 3_600
            return UsageTimeZoneOption(
                id: fixedSelection(offsetSeconds: seconds),
                title: offsetLabel(seconds: seconds)
            )
        }
        return [system] + fixed
    }

    static var configuredSelection: String {
        normalizedSelection(
            UserDefaults.standard.string(forKey: configuredSelectionKey) ?? systemSelection
        )
    }

    static var configuredTimeZone: TimeZone {
        timeZone(for: configuredSelection)
    }

    static var configuredTimeZoneLabel: String {
        offsetLabel(seconds: configuredTimeZone.secondsFromGMT(for: Date()))
    }

    /// Date-only CSV rows inherit the zone used by the export that produced them.
    /// Existing pre-timezone caches remain UTC until a new import succeeds.
    static var timeZone: TimeZone {
        guard UserDefaults.standard.object(forKey: importedOffsetKey) != nil else {
            return TimeZone(secondsFromGMT: 0)!
        }
        let seconds = UserDefaults.standard.integer(forKey: importedOffsetKey)
        return TimeZone(secondsFromGMT: seconds) ?? TimeZone(secondsFromGMT: 0)!
    }

    static var timeZoneLabel: String {
        offsetLabel(seconds: timeZone.secondsFromGMT(for: Date()))
    }

    static func setConfiguredSelection(_ selection: String) {
        UserDefaults.standard.set(normalizedSelection(selection), forKey: configuredSelectionKey)
    }

    static func markImported(using timeZone: TimeZone, referenceDate: Date = Date()) {
        let seconds = timeZone.secondsFromGMT(for: referenceDate)
        UserDefaults.standard.set(seconds, forKey: importedOffsetKey)
    }

    static func clearImportedTimeZone() {
        UserDefaults.standard.removeObject(forKey: importedOffsetKey)
    }

    static func timeZone(for selection: String, referenceDate: Date = Date()) -> TimeZone {
        let normalized = normalizedSelection(selection)
        guard normalized != systemSelection,
              let seconds = Int(normalized.dropFirst(fixedOffsetPrefix.count)),
              let fixed = TimeZone(secondsFromGMT: seconds) else {
            return .current
        }
        return fixed
    }

    static func normalizedSelection(_ selection: String) -> String {
        guard selection != systemSelection,
              selection.hasPrefix(fixedOffsetPrefix),
              let seconds = Int(selection.dropFirst(fixedOffsetPrefix.count)),
              seconds.isMultiple(of: 3_600),
              (-12 * 3_600...14 * 3_600).contains(seconds) else {
            return systemSelection
        }
        return fixedSelection(offsetSeconds: seconds)
    }

    static func fixedSelection(offsetSeconds: Int) -> String {
        "\(fixedOffsetPrefix)\(offsetSeconds)"
    }

    static func offsetLabel(seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let absolute = abs(seconds)
        let hours = absolute / 3_600
        let minutes = (absolute % 3_600) / 60
        return String(format: "UTC%@%02d:%02d", sign, hours, minutes)
    }

    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static var calendar: Calendar {
        calendar(in: timeZone)
    }

    static func formatter(_ dateFormat: String, timeZone: TimeZone = UsageTime.timeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        return formatter
    }

    static func day(from raw: String, timeZone: TimeZone = UsageTime.timeZone) -> Date? {
        guard let date = formatter("yyyy-MM-dd", timeZone: timeZone).date(from: raw) else { return nil }
        return calendar(in: timeZone).startOfDay(for: date)
    }

    static func isSameDay(_ raw: String, as referenceDate: Date, timeZone: TimeZone = UsageTime.timeZone) -> Bool {
        guard let date = day(from: raw, timeZone: timeZone) else { return false }
        return calendar(in: timeZone).isDate(date, inSameDayAs: referenceDate)
    }

    static func isSameMonth(_ raw: String, as referenceDate: Date, timeZone: TimeZone = UsageTime.timeZone) -> Bool {
        guard let date = day(from: raw, timeZone: timeZone) else { return false }
        let calendar = calendar(in: timeZone)
        let dateComponents = calendar.dateComponents([.year, .month], from: date)
        let referenceComponents = calendar.dateComponents([.year, .month], from: referenceDate)
        return dateComponents == referenceComponents
    }
}

struct UsageExportRequestConfiguration: Equatable {
    let startSeconds: Int
    let endSeconds: Int
    let timeZoneOffsetSeconds: Int
    let startDate: String
    let endDateExclusive: String

    static func make(
        referenceDate: Date = Date(),
        timeZone: TimeZone,
        inclusiveDayCount: Int = 31
    ) -> UsageExportRequestConfiguration {
        let calendar = UsageTime.calendar(in: timeZone)
        let dayCount = max(1, min(inclusiveDayCount, 31))
        let today = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let formatter = UsageTime.formatter("yyyy-MM-dd", timeZone: timeZone)

        return UsageExportRequestConfiguration(
            startSeconds: Int(start.timeIntervalSince1970),
            endSeconds: Int(end.timeIntervalSince1970),
            timeZoneOffsetSeconds: timeZone.secondsFromGMT(for: referenceDate),
            startDate: formatter.string(from: start),
            endDateExclusive: formatter.string(from: end)
        )
    }
}

func normalizedCurrencyCode(_ raw: String) -> String {
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return normalized.isEmpty ? "CNY" : normalized
}

func currencySymbol(for currencyCode: String) -> String {
    switch normalizedCurrencyCode(currencyCode) {
    case "CNY": return "¥"
    case "USD": return "$"
    default: return "\(normalizedCurrencyCode(currencyCode)) "
    }
}

func formattedCurrency(_ value: Double, currencyCode: String) -> String {
    "\(currencySymbol(for: currencyCode))\(String(format: "%.2f", value))"
}

func formattedCurrency(_ value: Decimal, currencyCode: String) -> String {
    formattedCurrency(NSDecimalNumber(decimal: value).doubleValue, currencyCode: currencyCode)
}

func decimalAmount(fromCents cents: Int) -> Decimal {
    Decimal(cents) / Decimal(100)
}

func roundedCents(from amount: Decimal) -> Int {
    var amount = amount
    var hundred = Decimal(100)
    var cents = Decimal()
    NSDecimalMultiply(&cents, &amount, &hundred, .plain)

    var rounded = Decimal()
    NSDecimalRound(&rounded, &cents, 0, .plain)
    return NSDecimalNumber(decimal: rounded).intValue
}

// MARK: - DeepSeek API 响应模型

/// 余额查询响应
/// 接口: GET https://api.deepseek.com/user/balance
struct BalanceResponse: Codable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    /// Prefer CNY when DeepSeek returns multiple currency balances.
    /// The API can change the order of balance_infos, so callers should not
    /// rely on the first item being the display currency.
    var preferredBalanceInfo: BalanceInfo? {
        if let cny = balanceInfos.first(where: { $0.currency.caseInsensitiveCompare("CNY") == .orderedSame }) {
            return cny
        }
        if let nonZero = balanceInfos.first(where: { (Double($0.totalBalance) ?? 0) > 0 }) {
            return nonZero
        }
        return balanceInfos.first
    }
}

struct BalanceInfo: Codable {
    let currency: String         // 货币类型，如 "CNY"
    let totalBalance: String     // 总余额
    let grantedBalance: String   // 赠送余额
    let toppedUpBalance: String  // 充值余额

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

/// 用量查询响应
/// 接口: GET https://api.deepseek.com/v1/usage?start_date=&end_date=
struct UsageResponse: Codable {
    let data: [UsageRecord]
}

struct UsageRecord: Codable, Identifiable {
    let id: String
    let modelName: String       // 模型名称: "deepseek-chat", "deepseek-reasoner" 等
    let totalTokens: Int        // 总 Token 消耗
    let promptTokens: Int       // 输入 Token
    let inputCacheHitTokens: Int
    let inputCacheMissTokens: Int
    let completionTokens: Int   // 输出 Token
    let costByCurrency: [String: Decimal]
    let date: String            // 日期 "2026-01-01"
    let requestCount: Int       // 请求次数

    var primaryCurrencyCode: String {
        if costByCurrency.keys.contains("CNY") {
            return "CNY"
        }
        return costByCurrency.keys.sorted().first ?? "CNY"
    }

    var costInCents: Int {
        costInCents(for: primaryCurrencyCode)
    }

    func costAmount(for currencyCode: String) -> Decimal {
        let normalized = normalizedCurrencyCode(currencyCode)
        return costByCurrency[normalized] ?? .zero
    }

    func costInCents(for currencyCode: String) -> Int {
        roundedCents(from: costAmount(for: currencyCode))
    }

    func replacingCosts(_ costs: [String: Decimal]) -> UsageRecord {
        UsageRecord(
            id: id,
            modelName: modelName,
            totalTokens: totalTokens,
            promptTokens: promptTokens,
            inputCacheHitTokens: inputCacheHitTokens,
            inputCacheMissTokens: inputCacheMissTokens,
            completionTokens: completionTokens,
            costByCurrency: costs,
            date: date,
            requestCount: requestCount
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case modelName = "model_name"
        case totalTokens = "total_tokens"
        case promptTokens = "prompt_tokens"
        case inputCacheHitTokens = "input_cache_hit_tokens"
        case inputCacheMissTokens = "input_cache_miss_tokens"
        case completionTokens = "completion_tokens"
        case costInCents = "cost_in_cents"
        case costByCurrency = "cost_by_currency"
        case currency
        case date
        case requestCount = "request_count"
    }

    init(
        id: String,
        modelName: String,
        totalTokens: Int,
        promptTokens: Int,
        inputCacheHitTokens: Int = 0,
        inputCacheMissTokens: Int = 0,
        completionTokens: Int,
        costInCents: Int,
        date: String,
        requestCount: Int = 0
    ) {
        self.id = id
        self.modelName = modelName
        self.totalTokens = totalTokens
        self.promptTokens = promptTokens
        self.inputCacheHitTokens = inputCacheHitTokens
        self.inputCacheMissTokens = inputCacheMissTokens
        self.completionTokens = completionTokens
        self.costByCurrency = ["CNY": decimalAmount(fromCents: costInCents)]
        self.date = date
        self.requestCount = requestCount
    }

    init(
        id: String,
        modelName: String,
        totalTokens: Int,
        promptTokens: Int,
        inputCacheHitTokens: Int = 0,
        inputCacheMissTokens: Int = 0,
        completionTokens: Int,
        costByCurrency: [String: Decimal],
        date: String,
        requestCount: Int = 0
    ) {
        self.id = id
        self.modelName = modelName
        self.totalTokens = totalTokens
        self.promptTokens = promptTokens
        self.inputCacheHitTokens = inputCacheHitTokens
        self.inputCacheMissTokens = inputCacheMissTokens
        self.completionTokens = completionTokens
        self.costByCurrency = Dictionary(uniqueKeysWithValues: costByCurrency.map {
            (normalizedCurrencyCode($0.key), $0.value)
        })
        self.date = date
        self.requestCount = requestCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        modelName = try container.decode(String.self, forKey: .modelName)
        totalTokens = try container.decode(Int.self, forKey: .totalTokens)
        promptTokens = try container.decode(Int.self, forKey: .promptTokens)
        inputCacheHitTokens = try container.decodeIfPresent(Int.self, forKey: .inputCacheHitTokens) ?? 0
        inputCacheMissTokens = try container.decodeIfPresent(Int.self, forKey: .inputCacheMissTokens) ?? 0
        completionTokens = try container.decode(Int.self, forKey: .completionTokens)
        if let decodedCosts = try container.decodeIfPresent([String: Decimal].self, forKey: .costByCurrency) {
            costByCurrency = Dictionary(uniqueKeysWithValues: decodedCosts.map {
                (normalizedCurrencyCode($0.key), $0.value)
            })
        } else {
            let legacyCents = try container.decodeIfPresent(Int.self, forKey: .costInCents) ?? 0
            let currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "CNY"
            costByCurrency = [normalizedCurrencyCode(currency): decimalAmount(fromCents: legacyCents)]
        }
        date = try container.decode(String.self, forKey: .date)
        requestCount = try container.decodeIfPresent(Int.self, forKey: .requestCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(totalTokens, forKey: .totalTokens)
        try container.encode(promptTokens, forKey: .promptTokens)
        try container.encode(inputCacheHitTokens, forKey: .inputCacheHitTokens)
        try container.encode(inputCacheMissTokens, forKey: .inputCacheMissTokens)
        try container.encode(completionTokens, forKey: .completionTokens)
        try container.encode(costByCurrency, forKey: .costByCurrency)
        try container.encode(costInCents, forKey: .costInCents)
        try container.encode(primaryCurrencyCode, forKey: .currency)
        try container.encode(date, forKey: .date)
        try container.encode(requestCount, forKey: .requestCount)
    }
}

// MARK: - 本地展示模型

/// 模型显示名称映射
enum DeepSeekModel: String, CaseIterable {
    case flash  = "deepseek-chat"      // V4 Flash
    case pro    = "deepseek-reasoner"   // V4 Pro (推理模型)

    var displayName: String {
        switch self {
        case .flash: return "V4 Flash"
        case .pro:   return "V4 Pro"
        }
    }

    var shortName: String {
        switch self {
        case .flash: return "Flash"
        case .pro:   return "Pro"
        }
    }

    var systemImageName: String {
        switch self {
        case .flash: return "bolt.fill"
        case .pro:   return "brain.head.profile"
        }
    }

    /// Token 单价（每百万 Token，单位：元）
    /// 根据 DeepSeek 官方定价
    var inputPricePerMillion: Double {
        switch self {
        case .flash: return 0.5   // 举例，以实际为准
        case .pro:   return 2.0
        }
    }

    var outputPricePerMillion: Double {
        switch self {
        case .flash: return 2.0
        case .pro:   return 8.0
        }
    }
}

/// 聚合后的模型用量数据
struct ModelUsageSummary: Identifiable {
    let id = UUID()
    let model: DeepSeekModel
    let totalTokens: Int
    let costAmount: Decimal
    let currencyCode: String

    var costInCents: Int {
        roundedCents(from: costAmount)
    }

    var totalTokensFormatted: String {
        formatNumber(totalTokens)
    }

    var costFormatted: String {
        formattedCurrency(costAmount, currencyCode: currencyCode)
    }
}

struct ModelDailyUsagePoint: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let totalTokens: Int
    let inputCacheHitTokens: Int
    let inputCacheMissTokens: Int
    let outputTokens: Int
    let requestCount: Int
}

/// Dashboard 整体状态
struct DashboardState {
    var isAvailable: Bool = false
    var totalBalance: Double = 0
    var grantedBalance: Double = 0
    var toppedUpBalance: Double = 0
    var modelUsage: [DeepSeekModel: ModelUsageSummary] = [:]
    var lastUpdated: Date?
    var isLoading: Bool = false
    var errorMessage: String?
}

// MARK: - Helpers

func formatNumber(_ number: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
}

// MARK: - Widget Snapshot (shared with Widget Extension via App Group)

struct WidgetSnapshot: Codable {
    let isWidgetEnabled: Bool
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
}
