import Foundation

enum UsageCSVImportError: LocalizedError {
    case unreadableFile
    case emptyFile
    case unsupportedColumns
    case noValidRows
    case invalidExportArchive(String)
    case staleExportRange(
        actualStartDate: String,
        actualEndDateExclusive: String,
        expectedStartDate: String,
        expectedEndDateExclusive: String
    )
    case recordsOutsideExportRange(startDate: String, endDateExclusive: String)
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
        case .invalidExportArchive(let reason):
            return "DeepSeek 用量 ZIP 无效：\(reason)"
        case .staleExportRange(
            let actualStartDate,
            let actualEndDateExclusive,
            let expectedStartDate,
            let expectedEndDateExclusive
        ):
            return "导出范围为 \(actualStartDate) 至 \(actualEndDateExclusive)，当前应为 \(expectedStartDate) 至 \(expectedEndDateExclusive)（官方导出时区），已保留现有用量数据"
        case .recordsOutsideExportRange(let startDate, let endDateExclusive):
            return "CSV 内容包含 \(startDate) 至 \(endDateExclusive) 范围外的数据，已拒绝导入"
        case .detailed(let message):
            return message
        }
    }
}

struct UsageCSVImportResult {
    let records: [UsageRecord]
    let timeZoneSecondsFromGMT: Int?
    let fileNameEndDateIsInclusive: Bool

    var timeZone: TimeZone? {
        timeZoneSecondsFromGMT.flatMap(TimeZone.init(secondsFromGMT:))
    }
}

enum UsageCSVImporter {
    static func importRecords(
        from url: URL,
        costURL: URL? = nil,
        defaultCurrencyCode: String = "CNY"
    ) throws -> [UsageRecord] {
        try importResult(
            from: url,
            costURL: costURL,
            defaultCurrencyCode: defaultCurrencyCode
        ).records
    }

    static func importResult(
        from url: URL,
        costURL: URL? = nil,
        defaultCurrencyCode: String = "CNY"
    ) throws -> UsageCSVImportResult {
        let amount = try importBaseRecords(
            from: url,
            defaultCurrencyCode: defaultCurrencyCode
        )
        guard let costURL else {
            return UsageCSVImportResult(
                records: amount.records,
                timeZoneSecondsFromGMT: amount.timeZoneSecondsFromGMT,
                fileNameEndDateIsInclusive: amount.fileNameEndDateIsInclusive
            )
        }

        let cost = try importCostExport(from: costURL)
        let sharedDates = Set(amount.timeZoneOffsetsByDate.keys)
            .intersection(cost.timeZoneOffsetsByDate.keys)
        guard sharedDates.allSatisfy({
            amount.timeZoneOffsetsByDate[$0] == cost.timeZoneOffsetsByDate[$0]
        }) else {
            throw UsageCSVImportError.detailed("amount 与 cost CSV 的导出时区不一致")
        }
        return UsageCSVImportResult(
            records: merge(amountRecords: amount.records, exactCosts: cost.costs),
            timeZoneSecondsFromGMT: amount.timeZoneSecondsFromGMT ?? cost.timeZoneSecondsFromGMT,
            fileNameEndDateIsInclusive: amount.fileNameEndDateIsInclusive
        )
    }

    private struct ParsedRecords {
        let records: [UsageRecord]
        let timeZoneSecondsFromGMT: Int?
        let timeZoneOffsetsByDate: [String: Int]
        let fileNameEndDateIsInclusive: Bool
    }

    private struct ParsedCosts {
        let costs: [String: [String: Decimal]]
        let timeZoneSecondsFromGMT: Int?
        let timeZoneOffsetsByDate: [String: Int]
    }

    private static func importBaseRecords(
        from url: URL,
        defaultCurrencyCode: String
    ) throws -> ParsedRecords {
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
            (hasRecognizedDateColumns(in: headers) &&
             firstIndex(in: headers, matching: ["type"]) != nil &&
             firstIndex(in: headers, matching: ["amount"]) != nil)

        if looksLikeAmountExport {
            return try importAmountExport(
                rows: rows,
                headers: headers,
                defaultCurrencyCode: defaultCurrencyCode
            )
        }

        let dateIndex = firstIndex(in: headers, matching: ["date", "day", "日期", "时间"])
        let modelIndex = firstIndex(in: headers, matching: ["model", "模型"])
        let inputIndex = firstIndex(in: headers, matching: ["prompttokens", "inputtokens", "输入token", "输入tokens"])
        let outputIndex = firstIndex(in: headers, matching: ["completiontokens", "outputtokens", "输出token", "输出tokens"])
        let totalIndex = firstIndex(in: headers, matching: ["totaltokens", "总token", "总tokens"])
        let amountIndex = firstIndex(in: headers, matching: ["amount", "cost", "fee", "金额", "费用", "花费"])
        let currencyIndex = firstIndex(in: headers, matching: ["currency", "币种", "货币"])
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
            let costAmount = parseAmount(
                value(at: amountIndex, in: row),
                header: amountIndex.flatMap { headers[$0] }
            )
            let rawCurrency = value(at: currencyIndex, in: row)
            let currencyCode = rawCurrency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? normalizedCurrencyCode(defaultCurrencyCode)
                : normalizedCurrencyCode(rawCurrency)

            guard totalTokens > 0 || costAmount > 0 || requestCount > 0 else { continue }

            records.append(
                UsageRecord(
                    id: "\(date)-\(model)-\(offset)",
                    modelName: model,
                    totalTokens: totalTokens,
                    promptTokens: promptTokens,
                    inputCacheHitTokens: 0,
                    inputCacheMissTokens: promptTokens,
                    completionTokens: completionTokens,
                    costByCurrency: [currencyCode: costAmount],
                    date: date,
                    requestCount: requestCount
                )
            )
        }

        guard records.isEmpty == false else {
            throw UsageCSVImportError.noValidRows
        }

        return ParsedRecords(
            records: records,
            timeZoneSecondsFromGMT: nil,
            timeZoneOffsetsByDate: [:],
            fileNameEndDateIsInclusive: false
        )
    }

    private enum DateColumns {
        case legacy(index: Int, timeZoneSecondsFromGMT: Int?)
        case interval(startIndex: Int, endIndex: Int)

        var timeZoneSecondsFromGMT: Int? {
            switch self {
            case .legacy(_, let timeZoneSecondsFromGMT):
                return timeZoneSecondsFromGMT
            case .interval:
                return nil
            }
        }

        var fileNameEndDateIsInclusive: Bool {
            // Current ISO interval exports name the selected final calendar day;
            // legacy utc_date exports used an exclusive filename boundary.
            switch self {
            case .legacy:
                return false
            case .interval:
                return true
            }
        }
    }

    private struct DateBucket {
        let date: String
        let timeZoneSecondsFromGMT: Int?
        let instant: Date?
    }

    private static func resolveDateColumns(in headers: [String]) throws -> DateColumns {
        let startIndex = headers.firstIndex(of: "starttimeiso")
        let endIndex = headers.firstIndex(of: "endtimeiso")
        if startIndex != nil || endIndex != nil {
            guard let startIndex, let endIndex else {
                throw UsageCSVImportError.detailed(
                    "CSV 时间列不完整，必须同时包含 start_time_iso 和 end_time_iso"
                )
            }
            return .interval(startIndex: startIndex, endIndex: endIndex)
        }

        if let utcDateIndex = headers.firstIndex(of: "utcdate") {
            return .legacy(index: utcDateIndex, timeZoneSecondsFromGMT: 0)
        }
        if let dateIndex = firstIndex(in: headers, matching: ["date", "day", "日期", "时间"]) {
            return .legacy(index: dateIndex, timeZoneSecondsFromGMT: nil)
        }
        throw UsageCSVImportError.unsupportedColumns
    }

    private static func hasRecognizedDateColumns(in headers: [String]) -> Bool {
        headers.contains("utcdate") ||
            (headers.contains("starttimeiso") && headers.contains("endtimeiso")) ||
            firstIndex(in: headers, matching: ["date", "day", "日期", "时间"]) != nil
    }

    private static func importAmountExport(
        rows: [[String]],
        headers: [String],
        defaultCurrencyCode: String
    ) throws -> ParsedRecords {
        let dateColumns = try resolveDateColumns(in: headers)
        guard let modelIndex = firstIndex(in: headers, matching: ["model", "模型"]),
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
            var costAmount = Decimal.zero
            var requestCount = 0
        }

        var aggregates: [String: Aggregate] = [:]
        var validDateCount = 0
        var validModelCount = 0
        var validTokenRowCount = 0
        var latestTimeZone: (instant: Date, secondsFromGMT: Int)?
        var timeZoneOffsetsByDate: [String: Int] = [:]

        for (offset, row) in rows.dropFirst().enumerated() {
            guard rowContainsData(row) else { continue }
            guard let bucket = try dateBucket(
                from: row,
                columns: dateColumns,
                csvKind: "amount",
                rowNumber: offset + 2
            ) else { continue }
            let date = bucket.date
            validDateCount += 1
            updateLatestTimeZone(&latestTimeZone, from: bucket)
            try recordTimeZone(
                from: bucket,
                in: &timeZoneOffsetsByDate,
                csvKind: "amount",
                rowNumber: offset + 2
            )

            let rawModel = value(at: modelIndex, in: row)
            guard let model = normalizedModel(from: rawModel) else { continue }
            validModelCount += 1

            let entryType = normalizeHeader(value(at: typeIndex, in: row))
            let amountValue = parseInteger(value(at: amountIndex, in: row))
            let costAmount = parseUnitCost(
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

            guard amountValue > 0 || costAmount > 0 else { continue }
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
            aggregate.costAmount += costAmount
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
                costByCurrency: [normalizedCurrencyCode(defaultCurrencyCode): aggregate.costAmount],
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
            throw UsageCSVImportError.detailed(
                "amount CSV 未聚合出有效用量记录：日期行 \(validDateCount)，模型行 \(validModelCount)，token 行 \(validTokenRowCount)"
            )
        }

        return ParsedRecords(
            records: records,
            timeZoneSecondsFromGMT: dateColumns.timeZoneSecondsFromGMT ?? latestTimeZone?.secondsFromGMT,
            timeZoneOffsetsByDate: timeZoneOffsetsByDate,
            fileNameEndDateIsInclusive: dateColumns.fileNameEndDateIsInclusive
        )
    }

    private static func importCostExport(from url: URL) throws -> ParsedCosts {
        let raw: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            raw = utf8
        } else if let unicode = try? String(contentsOf: url, encoding: .unicode) {
            raw = unicode
        } else {
            throw UsageCSVImportError.unreadableFile
        }

        let rows = parseCSV(raw)
        guard let headerRow = rows.first, headerRow.isEmpty == false else {
            throw UsageCSVImportError.emptyFile
        }

        let headers = headerRow.map(normalizeHeader)
        let dateColumns = try resolveDateColumns(in: headers)
        guard let modelIndex = firstIndex(in: headers, matching: ["model", "模型"]),
              let costIndex = firstIndex(in: headers, matching: ["cost", "amount", "金额", "费用"]),
              let currencyIndex = firstIndex(in: headers, matching: ["currency", "币种", "货币"]) else {
            throw UsageCSVImportError.unsupportedColumns
        }

        var costs: [String: [String: Decimal]] = [:]
        var latestTimeZone: (instant: Date, secondsFromGMT: Int)?
        var timeZoneOffsetsByDate: [String: Int] = [:]
        for (offset, row) in rows.dropFirst().enumerated() {
            guard rowContainsData(row) else { continue }
            guard let bucket = try dateBucket(
                from: row,
                columns: dateColumns,
                csvKind: "cost",
                rowNumber: offset + 2
            ),
            let model = normalizedModel(from: value(at: modelIndex, in: row)) else {
                continue
            }
            let date = bucket.date
            updateLatestTimeZone(&latestTimeZone, from: bucket)
            try recordTimeZone(
                from: bucket,
                in: &timeZoneOffsetsByDate,
                csvKind: "cost",
                rowNumber: offset + 2
            )

            let amount = parseDecimal(value(at: costIndex, in: row))
            guard amount != .zero else { continue }

            let currency = normalizedCurrencyCode(value(at: currencyIndex, in: row))
            let key = "\(date)|\(model)"
            var byCurrency = costs[key] ?? [:]
            byCurrency[currency, default: .zero] += amount
            costs[key] = byCurrency
        }

        return ParsedCosts(
            costs: costs,
            timeZoneSecondsFromGMT: dateColumns.timeZoneSecondsFromGMT ?? latestTimeZone?.secondsFromGMT,
            timeZoneOffsetsByDate: timeZoneOffsetsByDate
        )
    }

    private static func merge(
        amountRecords: [UsageRecord],
        exactCosts: [String: [String: Decimal]]
    ) -> [UsageRecord] {
        var recordsByKey: [String: UsageRecord] = [:]
        for record in amountRecords {
            let key = "\(record.date)|\(record.modelName)"
            guard let existing = recordsByKey[key] else {
                recordsByKey[key] = record
                continue
            }

            var combinedCosts = existing.costByCurrency
            for (currency, amount) in record.costByCurrency {
                combinedCosts[currency, default: .zero] += amount
            }
            recordsByKey[key] = UsageRecord(
                id: key,
                modelName: record.modelName,
                totalTokens: existing.totalTokens + record.totalTokens,
                promptTokens: existing.promptTokens + record.promptTokens,
                inputCacheHitTokens: existing.inputCacheHitTokens + record.inputCacheHitTokens,
                inputCacheMissTokens: existing.inputCacheMissTokens + record.inputCacheMissTokens,
                completionTokens: existing.completionTokens + record.completionTokens,
                costByCurrency: combinedCosts,
                date: record.date,
                requestCount: existing.requestCount + record.requestCount
            )
        }

        for (key, costs) in exactCosts {
            if let record = recordsByKey[key] {
                recordsByKey[key] = record.replacingCosts(costs)
                continue
            }

            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            recordsByKey[key] = UsageRecord(
                id: key,
                modelName: parts[1],
                totalTokens: 0,
                promptTokens: 0,
                completionTokens: 0,
                costByCurrency: costs,
                date: parts[0],
                requestCount: 0
            )
        }

        return recordsByKey.values.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.modelName < rhs.modelName
            }
            return lhs.date < rhs.date
        }
    }

    private struct ISOEndpoint {
        let instant: Date
        let localDate: String
        let timeZoneSecondsFromGMT: Int
        let isMidnight: Bool
    }

    private static func dateBucket(
        from row: [String],
        columns: DateColumns,
        csvKind: String,
        rowNumber: Int
    ) throws -> DateBucket? {
        switch columns {
        case .legacy(let index, let timeZoneSecondsFromGMT):
            guard let date = normalizedDate(from: value(at: index, in: row)) else {
                return nil
            }
            return DateBucket(
                date: date,
                timeZoneSecondsFromGMT: timeZoneSecondsFromGMT,
                instant: nil
            )

        case .interval(let startIndex, let endIndex):
            let startText = value(at: startIndex, in: row)
            let endText = value(at: endIndex, in: row)
            let minimumDayDuration: TimeInterval = 20 * 60 * 60
            let maximumDayDuration: TimeInterval = 28 * 60 * 60
            guard let start = parseISOEndpoint(startText),
                  let end = parseISOEndpoint(endText),
                  start.isMidnight,
                  end.isMidnight,
                  end.instant > start.instant,
                  end.instant.timeIntervalSince(start.instant) >= minimumDayDuration,
                  end.instant.timeIntervalSince(start.instant) <= maximumDayDuration,
                  nextCalendarDate(after: start.localDate) == end.localDate else {
                throw UsageCSVImportError.detailed(
                    "\(csvKind) CSV 第 \(rowNumber) 行的时间区间无效"
                )
            }

            return DateBucket(
                date: start.localDate,
                timeZoneSecondsFromGMT: start.timeZoneSecondsFromGMT,
                instant: start.instant
            )
        }
    }

    private static func parseISOEndpoint(_ raw: String) -> ISOEndpoint? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d{4}-\d{2}-\d{2})[Tt](\d{2}:\d{2}:\d{2})(?:\.(\d+))?([Zz]|[+-]\d{2}:\d{2})$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              let dateText = capture(1, from: match, in: text),
              let timeText = capture(2, from: match, in: text),
              let zoneText = capture(4, from: match, in: text),
              let timeZoneSecondsFromGMT = parseTimeZoneOffset(zoneText),
              let timeZone = TimeZone(secondsFromGMT: timeZoneSecondsFromGMT),
              normalizedCalendarDate(dateText, timeZone: timeZone) == dateText else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = match.range(at: 3).location == NSNotFound
            ? [.withInternetDateTime]
            : [.withInternetDateTime, .withFractionalSeconds]
        guard let instant = formatter.date(from: text.uppercased()) else { return nil }

        let fractional = capture(3, from: match, in: text) ?? ""
        return ISOEndpoint(
            instant: instant,
            localDate: dateText,
            timeZoneSecondsFromGMT: timeZoneSecondsFromGMT,
            isMidnight: timeText == "00:00:00" && fractional.allSatisfy { $0 == "0" }
        )
    }

    private static func capture(
        _ index: Int,
        from match: NSTextCheckingResult,
        in text: String
    ) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    private static func parseTimeZoneOffset(_ raw: String) -> Int? {
        if raw.caseInsensitiveCompare("Z") == .orderedSame {
            return 0
        }

        guard raw.count == 6,
              let sign = raw.first,
              sign == "+" || sign == "-" else {
            return nil
        }
        let components = raw.dropFirst().split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              hours <= 18,
              minutes < 60 else {
            return nil
        }

        let seconds = (hours * 60 + minutes) * 60 * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds) == nil ? nil : seconds
    }

    private static func nextCalendarDate(after raw: String) -> String? {
        guard let day = UsageTime.day(from: raw),
              let next = UsageTime.calendar(in: UsageTime.defaultTimeZone).date(
                byAdding: .day,
                value: 1,
                to: day
              ) else {
            return nil
        }
        return UsageTime.formatter("yyyy-MM-dd").string(from: next)
    }

    private static func updateLatestTimeZone(
        _ latest: inout (instant: Date, secondsFromGMT: Int)?,
        from bucket: DateBucket
    ) {
        guard let instant = bucket.instant,
              let secondsFromGMT = bucket.timeZoneSecondsFromGMT else {
            return
        }
        if let current = latest, instant < current.instant {
            return
        } else {
            latest = (instant, secondsFromGMT)
        }
    }

    private static func recordTimeZone(
        from bucket: DateBucket,
        in offsetsByDate: inout [String: Int],
        csvKind: String,
        rowNumber: Int
    ) throws {
        guard let secondsFromGMT = bucket.timeZoneSecondsFromGMT else { return }
        if let existing = offsetsByDate[bucket.date], existing != secondsFromGMT {
            throw UsageCSVImportError.detailed(
                "\(csvKind) CSV 第 \(rowNumber) 行的导出时区不一致"
            )
        }
        offsetsByDate[bucket.date] = secondsFromGMT
    }

    private static func rowContainsData(_ row: [String]) -> Bool {
        row.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
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
            .replacingOccurrences(of: "\u{FEFF}", with: "")
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
            return normalizedCalendarDate("\(year)-\(month)-\(day)")
        }

        if text.count >= 10 {
            let prefix = String(text.prefix(10)).replacingOccurrences(of: "/", with: "-")
            if prefix.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
               let normalized = normalizedCalendarDate(prefix) {
                return normalized
            }
        }

        return nil
    }

    private static func normalizedCalendarDate(
        _ raw: String,
        timeZone: TimeZone = UsageTime.defaultTimeZone
    ) -> String? {
        let formatter = UsageTime.formatter("yyyy-MM-dd", timeZone: timeZone)
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else {
            return nil
        }
        return raw
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

    private static func parseDecimal(_ raw: String) -> Decimal {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) ?? .zero
    }

    private static func parseAmount(_ raw: String, header: String?) -> Decimal {
        let amount = parseDecimal(raw)
        let normalizedHeader = header ?? ""
        if normalizedHeader.contains("cent") || normalizedHeader.contains("分") {
            return amount / Decimal(100)
        }
        return amount
    }

    private static func parseUnitCost(_ raw: String, multiplier: Int) -> Decimal {
        let parsedUnitPrice = parseDecimal(raw)
        guard multiplier > 0, parsedUnitPrice != .zero else {
            return .zero
        }

        var unitPrice = parsedUnitPrice
        var amount = Decimal(multiplier)
        var cost = Decimal()
        NSDecimalMultiply(&cost, &unitPrice, &amount, .plain)
        return cost
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        // Swift can treat CRLF as one grapheme cluster, so normalize line endings
        // before parsing official Windows-style exports.
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let characters = Array(normalizedText)
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
