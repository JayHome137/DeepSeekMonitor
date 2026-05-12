import Foundation

enum UsageCSVImportError: LocalizedError {
    case unreadableFile
    case emptyFile
    case unsupportedColumns
    case noValidRows
    case detailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "无法读取 CSV 文件"
        case .emptyFile:
            return "CSV 文件为空"
        case .unsupportedColumns:
            return "CSV 列名无法识别，请选择 DeepSeek Usage 导出的 amount CSV"
        case .noValidRows:
            return "CSV 中没有可导入的有效用量记录"
        case .detailed(let message):
            return message
        }
    }
}

enum UsageCSVImporter {
    static func importRecords(from url: URL) throws -> [UsageRecord] {
        let raw: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            raw = utf8
        } else if let unicode = try? String(contentsOf: url, encoding: .unicode) {
            raw = unicode
        } else {
            throw UsageCSVImportError.unreadableFile
        }

        let rows = parseCSV(raw)
        guard let headerRow = rows.first, !headerRow.isEmpty else {
            throw UsageCSVImportError.emptyFile
        }

        let headers = headerRow.map(normalizeHeader)
        let fileName = url.lastPathComponent.lowercased()
        let looksLikeAmountExport =
            fileName.contains("amount") ||
            (firstIndex(in: headers, matching: ["utcdate"]) != nil &&
             firstIndex(in: headers, matching: ["type"]) != nil &&
             firstIndex(in: headers, matching: ["amount"]) != nil)

        if looksLikeAmountExport {
            return try importAmountExport(rawText: raw, rows: rows, headers: headers)
        }

        let dateIndex = firstIndex(in: headers, matching: ["date", "day", "日期", "时间"])
        let modelIndex = firstIndex(in: headers, matching: ["model", "模型"])
        let inputIndex = firstIndex(in: headers, matching: ["prompttokens", "inputtokens", "输入token", "输入tokens"])
        let outputIndex = firstIndex(in: headers, matching: ["completiontokens", "outputtokens", "输出token", "输出tokens"])
        let totalIndex = firstIndex(in: headers, matching: ["totaltokens", "总token", "总tokens"])
        let amountIndex = firstIndex(in: headers, matching: ["amount", "cost", "fee", "金额", "费用", "花费"])
        let requestCountIndex = firstIndex(in: headers, matching: ["requestcount", "requests", "请求次数"])

        guard let resolvedDateIndex = dateIndex, let resolvedModelIndex = modelIndex else {
            throw UsageCSVImportError.unsupportedColumns
        }

        var records: [UsageRecord] = []
        for (offset, row) in rows.dropFirst().enumerated() {
            guard row.isEmpty == false else { continue }
            guard let date = normalizedDate(from: value(at: resolvedDateIndex, in: row)),
                  let model = normalizedModel(from: value(at: resolvedModelIndex, in: row)) else {
                continue
            }

            let promptTokens = parseInteger(value(at: inputIndex, in: row))
            let completionTokens = parseInteger(value(at: outputIndex, in: row))
            let parsedTotalTokens = parseInteger(value(at: totalIndex, in: row))
            let totalTokens = max(parsedTotalTokens, promptTokens + completionTokens)
            let requestCount = parseInteger(value(at: requestCountIndex, in: row))
            let costInCents = parseAmountInCents(
                value(at: amountIndex, in: row),
                header: amountIndex.flatMap { headers[$0] }
            )

            guard totalTokens > 0 || costInCents > 0 || requestCount > 0 else { continue }

            records.append(
                UsageRecord(
                    id: "\(date)-\(model)-\(offset)",
                    modelName: model,
                    totalTokens: totalTokens,
                    promptTokens: promptTokens,
                    inputCacheHitTokens: 0,
                    inputCacheMissTokens: promptTokens,
                    completionTokens: completionTokens,
                    costInCents: costInCents,
                    date: date,
                    requestCount: requestCount
                )
            )
        }

        guard records.isEmpty == false else {
            let sampleRows = rows.dropFirst().prefix(2).map { row in
                row.joined(separator: " | ")
            }.joined(separator: ", ")
            let headerSummary = headers.joined(separator: ", ")
            throw UsageCSVImportError.detailed("CSV 未导入出有效记录，表头: \(headerSummary)，示例: \(sampleRows)")
        }

        return records
    }

    private static func importAmountExport(rawText: String, rows: [[String]], headers: [String]) throws -> [UsageRecord] {
        // DeepSeek 导出的 amount CSV 结构稳定，优先按原始文本逐行解析，
        // 避免手写 CSV 解析器在某些编码/换行场景下把整行吃成一个字段。
        let rawLines = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        if rawLines.count > 1 {
            let directRecords = importAmountExportByColumns(lines: rawLines)
            if directRecords.isEmpty == false {
                return directRecords
            }
        }

        guard let dateIndex = firstIndex(in: headers, matching: ["utcdate", "date", "day", "日期", "时间"]),
              let modelIndex = firstIndex(in: headers, matching: ["model", "模型"]),
              let typeIndex = firstIndex(in: headers, matching: ["type", "类型"]),
              let amountIndex = firstIndex(in: headers, matching: ["amount", "数量"]),
              let priceIndex = firstIndex(in: headers, matching: ["price", "单价"]) else {
            throw UsageCSVImportError.unsupportedColumns
        }

        struct Aggregate {
            var promptTokens = 0
            var inputCacheHitTokens = 0
            var inputCacheMissTokens = 0
            var completionTokens = 0
            var totalTokens = 0
            var costInCents = 0
            var requestCount = 0
        }

        var aggregates: [String: Aggregate] = [:]
        var validDateCount = 0
        var validModelCount = 0
        var validTokenRowCount = 0

        for row in rows.dropFirst() {
            let rawDate = value(at: dateIndex, in: row)
            guard let date = normalizedDate(from: rawDate) else { continue }
            validDateCount += 1

            let rawModel = value(at: modelIndex, in: row)
            guard let model = normalizedModel(from: rawModel) else { continue }
            validModelCount += 1

            let entryType = normalizeHeader(value(at: typeIndex, in: row))
            let amountValue = parseInteger(value(at: amountIndex, in: row))
            let costInCents = parseUnitPriceInCents(
                value(at: priceIndex, in: row),
                multiplier: amountValue
            )

            let key = "\(date)|\(model)"
            var aggregate = aggregates[key] ?? Aggregate()

            if entryType.contains("requestcount") {
                guard amountValue > 0 else { continue }
                aggregate.requestCount += amountValue
                aggregates[key] = aggregate
                continue
            }

            guard amountValue > 0 || costInCents > 0 else { continue }
            guard entryType.contains("token") else { continue }
            validTokenRowCount += 1

            if entryType.contains("outputtokens") {
                aggregate.completionTokens += amountValue
            } else if entryType.contains("inputcachehittokens") {
                aggregate.promptTokens += amountValue
                aggregate.inputCacheHitTokens += amountValue
            } else if entryType.contains("inputcachemisstokens") {
                aggregate.promptTokens += amountValue
                aggregate.inputCacheMissTokens += amountValue
            } else {
                aggregate.promptTokens += amountValue
                aggregate.inputCacheMissTokens += amountValue
            }
            aggregate.totalTokens += amountValue
            aggregate.costInCents += costInCents
            aggregates[key] = aggregate
        }

        let records = aggregates.map { key, aggregate in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return UsageRecord(
                id: key,
                modelName: parts[1],
                totalTokens: aggregate.totalTokens,
                promptTokens: aggregate.promptTokens,
                inputCacheHitTokens: aggregate.inputCacheHitTokens,
                inputCacheMissTokens: aggregate.inputCacheMissTokens,
                completionTokens: aggregate.completionTokens,
                costInCents: aggregate.costInCents,
                date: parts[0],
                requestCount: aggregate.requestCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.modelName < rhs.modelName
            }
            return lhs.date < rhs.date
        }

        guard records.isEmpty == false else {
            let sampleTypes = rows.dropFirst().prefix(5).map { value(at: typeIndex, in: $0) }.joined(separator: ", ")
            throw UsageCSVImportError.detailed(
                "amount CSV 未聚合成功：日期行 \(validDateCount)，模型行 \(validModelCount)，token 行 \(validTokenRowCount)，示例 type: \(sampleTypes)"
            )
        }

        return records
    }

    private static func importAmountExportByColumns(lines: [String]) -> [UsageRecord] {
        struct Aggregate {
            var promptTokens = 0
            var inputCacheHitTokens = 0
            var inputCacheMissTokens = 0
            var completionTokens = 0
            var totalTokens = 0
            var costInCents = 0
            var requestCount = 0
        }

        var aggregates: [String: Aggregate] = [:]

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }

            let columns = trimmed
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

            guard columns.count >= 8 else { continue }

            guard let date = normalizedDate(from: columns[1]),
                  let model = normalizedModel(from: columns[2]) else {
                continue
            }

            let entryType = normalizeHeader(columns[5])
            let amountValue = parseInteger(columns[7])
            let costInCents = parseUnitPriceInCents(columns[6], multiplier: amountValue)

            let key = "\(date)|\(model)"
            var aggregate = aggregates[key] ?? Aggregate()

            if entryType.contains("requestcount") {
                guard amountValue > 0 else { continue }
                aggregate.requestCount += amountValue
                aggregates[key] = aggregate
                continue
            }

            guard amountValue > 0 || costInCents > 0 else { continue }
            guard entryType.contains("token") else { continue }

            if entryType.contains("outputtokens") {
                aggregate.completionTokens += amountValue
            } else if entryType.contains("inputcachehittokens") {
                aggregate.promptTokens += amountValue
                aggregate.inputCacheHitTokens += amountValue
            } else if entryType.contains("inputcachemisstokens") {
                aggregate.promptTokens += amountValue
                aggregate.inputCacheMissTokens += amountValue
            } else {
                aggregate.promptTokens += amountValue
                aggregate.inputCacheMissTokens += amountValue
            }
            aggregate.totalTokens += amountValue
            aggregate.costInCents += costInCents
            aggregates[key] = aggregate
        }

        return aggregates.map { key, aggregate in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return UsageRecord(
                id: key,
                modelName: parts[1],
                totalTokens: aggregate.totalTokens,
                promptTokens: aggregate.promptTokens,
                inputCacheHitTokens: aggregate.inputCacheHitTokens,
                inputCacheMissTokens: aggregate.inputCacheMissTokens,
                completionTokens: aggregate.completionTokens,
                costInCents: aggregate.costInCents,
                date: parts[0],
                requestCount: aggregate.requestCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.modelName < rhs.modelName
            }
            return lhs.date < rhs.date
        }
    }

    private static func value(at index: Int?, in row: [String]) -> String {
        guard let index, row.indices.contains(index) else { return "" }
        return row[index]
    }

    private static func firstIndex(in headers: [String], matching keywords: [String]) -> Int? {
        headers.firstIndex { header in
            keywords.contains { keyword in
                header.contains(normalizeHeader(keyword))
            }
        }
    }

    private static func normalizeHeader(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }

    private static func normalizedDate(from raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }

        if text.range(of: #"^\d{8}$"#, options: .regularExpression) != nil {
            let year = text.prefix(4)
            let month = text.dropFirst(4).prefix(2)
            let day = text.dropFirst(6).prefix(2)
            return "\(year)-\(month)-\(day)"
        }

        let fmts = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "yyyyMMdd",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        ]

        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        output.dateFormat = "yyyy-MM-dd"

        for pattern in fmts {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            if let date = formatter.date(from: text) {
                return output.string(from: date)
            }
        }

        if text.count >= 10 {
            let prefix = String(text.prefix(10)).replacingOccurrences(of: "/", with: "-")
            if prefix.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                return prefix
            }
        }

        return nil
    }

    private static func normalizedModel(from raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard text.isEmpty == false else { return nil }

        if text.contains("deepseek-v4-pro") || text.contains("deepseek-reasoner") || text.contains("reasoner") || text.contains("pro") {
            return DeepSeekModel.pro.rawValue
        }

        if text.contains("deepseek-v4-flash") || text.contains("deepseek-chat") || text.contains("flash") || text.contains("chat") {
            return DeepSeekModel.flash.rawValue
        }

        return text
    }

    private static func parseInteger(_ raw: String) -> Int {
        let digits = raw.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let integer = Int(digits) {
            return integer
        }
        if let decimal = Decimal(string: digits) {
            return NSDecimalNumber(decimal: decimal).intValue
        }
        return 0
    }

    private static func parseAmountInCents(_ raw: String, header: String?) -> Int {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.isEmpty == false else { return 0 }

        let normalizedHeader = header ?? ""
        if normalizedHeader.contains("cent") || normalizedHeader.contains("分") {
            return Int(cleaned) ?? 0
        }

        if let decimal = Decimal(string: cleaned) {
            var amount = decimal
            var multiplier = Decimal(100)
            var result = Decimal()
            NSDecimalMultiply(&result, &amount, &multiplier, .plain)
            return NSDecimalNumber(decimal: result).intValue
        }

        return Int(cleaned) ?? 0
    }

    private static func parseUnitPriceInCents(_ raw: String, multiplier: Int) -> Int {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.isEmpty == false, multiplier > 0, let decimal = Decimal(string: cleaned) else {
            return 0
        }

        var unitPrice = decimal
        var amount = Decimal(multiplier)
        var cost = Decimal()
        NSDecimalMultiply(&cost, &unitPrice, &amount, .plain)

        var hundred = Decimal(100)
        var cents = Decimal()
        NSDecimalMultiply(&cents, &cost, &hundred, .plain)
        return NSDecimalNumber(decimal: cents).intValue
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let char = characters[index]

            if char == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if (char == "\n" || char == "\r") && !inQuotes {
                if char == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                if row.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) {
                    rows.append(row)
                }
                row = []
                field = ""
            } else {
                field.append(char)
            }

            index += 1
        }

        if field.isEmpty == false || row.isEmpty == false {
            row.append(field)
            if row.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) {
                rows.append(row)
            }
        }

        return rows
    }
}
