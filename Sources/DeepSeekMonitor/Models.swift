import Foundation

enum UsageTime {
    static let defaultTimeZone = TimeZone(secondsFromGMT: 0)!

    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func formatter(
        _ dateFormat: String,
        timeZone: TimeZone = defaultTimeZone
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        formatter.isLenient = false
        return formatter
    }

    static func day(
        from raw: String,
        timeZone: TimeZone = defaultTimeZone
    ) -> Date? {
        guard let date = formatter("yyyy-MM-dd", timeZone: timeZone).date(from: raw) else {
            return nil
        }
        return calendar(in: timeZone).startOfDay(for: date)
    }

    static func isSameDay(
        _ raw: String,
        as referenceDate: Date,
        timeZone: TimeZone = defaultTimeZone
    ) -> Bool {
        guard let date = day(from: raw, timeZone: timeZone) else { return false }
        return calendar(in: timeZone).isDate(date, inSameDayAs: referenceDate)
    }

    static func isSameMonth(
        _ raw: String,
        as referenceDate: Date,
        timeZone: TimeZone = defaultTimeZone
    ) -> Bool {
        guard let date = day(from: raw, timeZone: timeZone) else { return false }
        let calendar = calendar(in: timeZone)
        let dateComponents = calendar.dateComponents([.year, .month], from: date)
        let referenceComponents = calendar.dateComponents([.year, .month], from: referenceDate)
        return dateComponents == referenceComponents
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
    formattedCurrency(Decimal(value), currencyCode: currencyCode)
}

func formattedCurrency(_ value: Decimal, currencyCode: String) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    formatter.roundingMode = .down
    let amount = formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
    return "\(currencySymbol(for: currencyCode))\(amount)"
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

func truncatedCents(from amount: Decimal) -> Int {
    var amount = amount
    var hundred = Decimal(100)
    var cents = Decimal()
    NSDecimalMultiply(&cents, &amount, &hundred, .plain)

    var truncated = Decimal()
    NSDecimalRound(&truncated, &cents, 0, .down)
    return NSDecimalNumber(decimal: truncated).intValue
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

    /// Select a display balance without combining currencies or converting them.
    var preferredBalanceInfo: BalanceInfo? {
        preferredBalanceInfo(matching: nil)
    }

    func preferredBalanceInfo(matching currencyCode: String?) -> BalanceInfo? {
        let nonZeroBalances = balanceInfos.filter {
            (Decimal(string: $0.totalBalance, locale: Locale(identifier: "en_US_POSIX")) ?? .zero) != .zero
        }

        if nonZeroBalances.count == 1 {
            return nonZeroBalances[0]
        }

        if let currencyCode {
            let preferredCode = normalizedCurrencyCode(currencyCode)
            if let matchingNonZero = nonZeroBalances.first(where: {
                normalizedCurrencyCode($0.currency) == preferredCode
            }) {
                return matchingNonZero
            }
            if nonZeroBalances.isEmpty,
               let matchingBalance = balanceInfos.first(where: {
                   normalizedCurrencyCode($0.currency) == preferredCode
               }) {
                return matchingBalance
            }
        }

        return nonZeroBalances.first ?? balanceInfos.first
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
        truncatedCents(from: costAmount)
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
    let lastUpdated: Date
}
