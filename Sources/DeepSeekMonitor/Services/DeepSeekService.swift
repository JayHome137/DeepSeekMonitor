import Foundation

// MARK: - API Errors

enum APIError: LocalizedError, Equatable {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(Int)
    case httpError(Int)
    case usageEndpointUnavailable
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:      return "API Key 未配置"
        case .invalidURL:    return "无效的 URL"
        case .invalidResponse: return "服务器返回无效响应"
        case .unauthorized:  return "API Key 无效或已过期"
        case .rateLimited:   return "请求过于频繁，请稍后重试"
        case .serverError(let code): return "服务器错误 (\(code))"
        case .httpError(let code):   return "HTTP 错误 (\(code))"
        case .usageEndpointUnavailable: return "DeepSeek 当前未公开用量查询接口，已仅显示余额"
        case .networkError(let msg): return "网络错误: \(msg)"
        case .decodingError(let msg): return "数据解析错误: \(msg)"
        }
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - DeepSeek API Service
//
// 封装 DeepSeek 官方 API 调用:
//   - GET /user/balance  →  查询账户余额
//   - GET /v1/usage      →  查询 Token 用量明细
//
// 使用: let service = DeepSeekService.shared
//       let balance = try await service.fetchBalance()

final class DeepSeekService {
    static let shared = DeepSeekService()

    private let baseURL = "https://api.deepseek.com"
    private let session: URLSession

    // MARK: - Init

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    // MARK: - API Key

    /// 是否已配置 API Key
    var hasAPIKey: Bool {
        (apiKey ?? "").isEmpty == false
    }

    /// 读取 API Key（本地构建版本使用 UserDefaults，避免频繁重建触发钥匙串授权弹窗）
    var apiKey: String? {
        get {
            UserDefaults.standard.string(forKey: "deepseek_api_key")
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: "deepseek_api_key")
            } else {
                UserDefaults.standard.removeObject(forKey: "deepseek_api_key")
            }
        }
    }

    /// 清除 API Key
    func clearAPIKey() {
        UserDefaults.standard.removeObject(forKey: "deepseek_api_key")
    }

    // MARK: - Balance

    /// 查询账户余额
    /// GET https://api.deepseek.com/user/balance
    func fetchBalance() async throws -> BalanceResponse {
        guard hasAPIKey else { throw APIError.noAPIKey }

        var request = URLRequest(url: try makeURL(path: "/user/balance"))
        request.httpMethod = "GET"
        setRequestHeaders(&request)

        return try await performRequest(request)
    }

    // MARK: - Usage

    /// 查询指定日期范围内的用量
    /// GET https://api.deepseek.com/v1/usage?start_date=&end_date=
    /// - Parameters:
    ///   - startDate: 起始日期（含）
    ///   - endDate:   截止日期（含）
    func fetchUsage(from startDate: Date, to endDate: Date) async throws -> UsageResponse {
        guard hasAPIKey else { throw APIError.noAPIKey }

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]

        var components = URLComponents(string: "\(baseURL)/v1/usage")!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: fmt.string(from: startDate)),
            URLQueryItem(name: "end_date",   value: fmt.string(from: endDate))
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        setRequestHeaders(&request)

        do {
            return try await performRequest(request)
        } catch let error as APIError {
            if case .httpError(let statusCode) = error, statusCode == 404 {
                throw APIError.usageEndpointUnavailable
            }
            throw error
        }
    }

    /// 获取最近 N 天的用量（便捷方法）
    func fetchRecentUsage(days: Int = 7) async throws -> UsageResponse {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -(days - 1), to: endDate)!
        return try await fetchUsage(from: startDate, to: endDate)
    }

    // MARK: - Request Helpers

    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        return url
    }

    private func setRequestHeaders(_ request: inout URLRequest) {
        request.setValue("Bearer \(apiKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    /// 通用请求执行方法
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        try validateResponse(response)

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// 响应状态码校验
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode)
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }
    }
}
