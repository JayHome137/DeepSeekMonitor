import Foundation

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
    let costInCents: Int        // 费用（分）
    let date: String            // 日期 "2026-01-01"
    let requestCount: Int       // 请求次数

    enum CodingKeys: String, CodingKey {
        case id
        case modelName = "model_name"
        case totalTokens = "total_tokens"
        case promptTokens = "prompt_tokens"
        case inputCacheHitTokens = "input_cache_hit_tokens"
        case inputCacheMissTokens = "input_cache_miss_tokens"
        case completionTokens = "completion_tokens"
        case costInCents = "cost_in_cents"
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
        self.costInCents = costInCents
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
        costInCents = try container.decode(Int.self, forKey: .costInCents)
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
        try container.encode(costInCents, forKey: .costInCents)
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
    let costInCents: Int

    var totalTokensFormatted: String {
        formatNumber(totalTokens)
    }

    var costFormatted: String {
        String(format: "¥%.2f", Double(costInCents) / 100.0)
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
