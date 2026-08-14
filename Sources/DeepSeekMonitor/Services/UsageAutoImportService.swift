import Foundation

enum UsageAutoImportService {
    private static let fingerprintKey = "auto_import_usage_fingerprint_v2"
    private static let rootFolderName = "usage-sync"
    private static let incomingFolderName = "incoming"
    private static let failedFolderName = "failed"
    private static let workspaceFolderName = "workspace"

    struct ImportCandidate {
        let sourceURL: URL
        let preparedAmountCSVURL: URL
        let preparedCostCSVURL: URL?
        let fingerprint: String
        let sourceName: String
        let selectedCSVNames: [String]
        let exportDateRange: ExportDateRange?
        let isArchive: Bool
    }

    struct ExportDateRange: Equatable {
        let startDate: String
        let endDateExclusive: String

        func contains(_ date: String) -> Bool {
            startDate <= date && date < endDateExclusive
        }
    }

    static func autoImportRootFolderURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let folder = base
            .appendingPathComponent("DeepSeekMonitor", isDirectory: true)
            .appendingPathComponent(rootFolderName, isDirectory: true)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        return folder
    }

    static func autoImportFolderURL() throws -> URL {
        let workspace = try autoImportRootFolderURL()
            .appendingPathComponent(workspaceFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: nil)
        return workspace
    }

    static func incomingFolderURL() throws -> URL {
        let incoming = try autoImportRootFolderURL()
            .appendingPathComponent(incomingFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true, attributes: nil)
        return incoming
    }

    static func failedFolderURL() throws -> URL {
        let failed = try autoImportRootFolderURL()
            .appendingPathComponent(failedFolderName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: failed,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return failed
    }

    static func watchedFolderURLs() throws -> [URL] {
        [try incomingFolderURL()]
    }

    static func nextImportCandidate(defaults: UserDefaults = .standard) throws -> ImportCandidate? {
        let incomingFolder = try incomingFolderURL()
        let candidates = try sourceCandidates(incomingFolder: incomingFolder)
        guard let latest = candidates.first else { return nil }

        let fingerprint = try fileFingerprint(for: latest)
        if defaults.string(forKey: fingerprintKey) == fingerprint {
            return nil
        }

        return try makeImportCandidate(from: latest, fingerprint: fingerprint)
    }

    static func prepareImportCandidate(from sourceURL: URL) throws -> ImportCandidate {
        let fingerprint = try fileFingerprint(for: sourceURL)
        return try makeImportCandidate(from: sourceURL, fingerprint: fingerprint)
    }

    static func importFingerprint(for sourceURL: URL) throws -> String {
        try fileFingerprint(for: sourceURL)
    }

    private static func makeImportCandidate(from sourceURL: URL, fingerprint: String) throws -> ImportCandidate {
        let sourceKind = detectFileKind(at: sourceURL)
        guard sourceKind != .unknown else {
            throw UsageCSVImportError.invalidExportArchive("文件不是有效的 ZIP 或 CSV")
        }

        let workspaceFolder = try autoImportFolderURL()
        let prepared = try prepareManagedCSV(from: sourceURL, workspaceFolder: workspaceFolder)
        let dateRange = try exportDateRange(from: prepared.selectedNames)
        if sourceKind == .zip, dateRange == nil {
            throw UsageCSVImportError.invalidExportArchive("amount/cost 文件名缺少官方日期范围")
        }

        return ImportCandidate(
            sourceURL: sourceURL,
            preparedAmountCSVURL: prepared.amountURL,
            preparedCostCSVURL: prepared.costURL,
            fingerprint: fingerprint,
            sourceName: sourceURL.lastPathComponent,
            selectedCSVNames: prepared.selectedNames,
            exportDateRange: dateRange,
            isArchive: sourceKind == .zip
        )
    }

    static func expectedRecentExportRange(
        referenceDate: Date = Date(),
        timeZone: TimeZone = UsageTime.defaultTimeZone
    ) -> ExportDateRange {
        let calendar = UsageTime.calendar(in: timeZone)
        let today = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let formatter = UsageTime.formatter("yyyy-MM-dd", timeZone: timeZone)
        return ExportDateRange(
            startDate: formatter.string(from: start),
            endDateExclusive: formatter.string(from: end)
        )
    }

    static func expectedCurrentMonthExportRange(
        referenceDate: Date = Date(),
        timeZone: TimeZone = UsageTime.defaultTimeZone
    ) -> ExportDateRange {
        currentMonthExportRanges(referenceDate: referenceDate, timeZone: timeZone).includingToday
    }

    private static func currentMonthExportRanges(
        referenceDate: Date,
        timeZone: TimeZone
    ) -> (excludingToday: ExportDateRange, includingToday: ExportDateRange) {
        let calendar = UsageTime.calendar(in: timeZone)
        let today = calendar.startOfDay(for: referenceDate)
        let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let formatter = UsageTime.formatter("yyyy-MM-dd", timeZone: timeZone)
        let startDate = formatter.string(from: monthStart)
        return (
            excludingToday: ExportDateRange(
                startDate: startDate,
                endDateExclusive: formatter.string(from: today)
            ),
            includingToday: ExportDateRange(
                startDate: startDate,
                endDateExclusive: formatter.string(from: tomorrow)
            )
        )
    }

    static func validateAutomaticExport(
        _ candidate: ImportCandidate,
        exportDateRange actualRange: ExportDateRange?,
        referenceDate: Date = Date(),
        timeZone: TimeZone
    ) throws {
        guard candidate.isArchive else {
            throw UsageCSVImportError.invalidExportArchive("自动网页导出必须返回官方 ZIP")
        }
        guard let actualRange else {
            throw UsageCSVImportError.invalidExportArchive("无法确认导出日期范围")
        }

        let expected = currentMonthExportRanges(
            referenceDate: referenceDate,
            timeZone: timeZone
        )
        let hasExpectedStart = actualRange.startDate == expected.includingToday.startDate
        let hasExpectedEnd =
            actualRange.endDateExclusive == expected.excludingToday.endDateExclusive ||
            actualRange.endDateExclusive == expected.includingToday.endDateExclusive
        guard hasExpectedStart, hasExpectedEnd else {
            throw UsageCSVImportError.staleExportRange(
                actualStartDate: actualRange.startDate,
                actualEndDateExclusive: actualRange.endDateExclusive,
                expectedStartDate: expected.includingToday.startDate,
                expectedEndDateExclusive: "\(expected.excludingToday.endDateExclusive) 或 \(expected.includingToday.endDateExclusive)"
            )
        }
    }

    static func resolvedExportDateRange(
        _ declaredRange: ExportDateRange?,
        records: [UsageRecord],
        fileNameEndDateIsInclusive: Bool
    ) throws -> ExportDateRange? {
        guard let declaredRange else { return nil }

        // Normalize both current inclusive filenames and legacy exclusive filenames
        // to the app's single internal [start, end) representation.
        let includesDeclaredEndDate = fileNameEndDateIsInclusive || records.contains {
            $0.date == declaredRange.endDateExclusive
        }
        let resolvedRange: ExportDateRange
        if includesDeclaredEndDate {
            guard let nextDate = nextCalendarDate(after: declaredRange.endDateExclusive) else {
                throw UsageCSVImportError.invalidExportArchive("导出文件名日期范围无效")
            }
            resolvedRange = ExportDateRange(
                startDate: declaredRange.startDate,
                endDateExclusive: nextDate
            )
        } else {
            resolvedRange = declaredRange
        }

        try validateRecords(records, within: resolvedRange)
        return resolvedRange
    }

    static func validateRecords(
        _ records: [UsageRecord],
        within range: ExportDateRange?
    ) throws {
        guard let range else { return }
        guard records.allSatisfy({ range.contains($0.date) }) else {
            throw UsageCSVImportError.recordsOutsideExportRange(
                startDate: range.startDate,
                endDateExclusive: range.endDateExclusive
            )
        }
    }

    static func exportDateRange(from fileNames: [String]) throws -> ExportDateRange? {
        let ranges = fileNames.compactMap(parseExportDateRange)
        guard let first = ranges.first else { return nil }
        guard ranges.count == fileNames.count else {
            throw UsageCSVImportError.invalidExportArchive("部分 CSV 文件名缺少官方日期范围")
        }
        guard ranges.allSatisfy({ $0 == first }) else {
            throw UsageCSVImportError.invalidExportArchive("amount 与 cost 的日期范围不一致")
        }
        return first
    }

    static func markImported(_ fingerprint: String, defaults: UserDefaults = .standard) {
        defaults.set(fingerprint, forKey: fingerprintKey)
    }

    static func hasImported(_ fingerprint: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: fingerprintKey) == fingerprint
    }

    /// 将自动导入失败的源文件移出监听目录，保留给手动排查或重新导入。
    @discardableResult
    static func quarantineFailedImport(
        _ sourceURL: URL,
        failedFolder: URL? = nil
    ) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw UsageCSVImportError.unreadableFile
        }

        let destinationFolder: URL
        if let failedFolder {
            destinationFolder = failedFolder
        } else {
            destinationFolder = try failedFolderURL()
        }
        try fileManager.createDirectory(
            at: destinationFolder,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var destination = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            let baseName = sourceURL.deletingPathExtension().lastPathComponent
            let pathExtension = sourceURL.pathExtension
            let uniqueName = pathExtension.isEmpty
                ? "\(baseName)-\(UUID().uuidString)"
                : "\(baseName)-\(UUID().uuidString).\(pathExtension)"
            destination = destinationFolder.appendingPathComponent(uniqueName)
        }

        try fileManager.moveItem(at: sourceURL, to: destination)
        return destination
    }

    static func cleanupImportedSources(keeping keepURL: URL?) throws {
        let incomingFolder = try incomingFolderURL()
        try cleanupCandidateFiles(in: incomingFolder, keeping: keepURL)
    }

    static func resetRememberedImport(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: fingerprintKey)
    }

    private static func sourceCandidates(incomingFolder: URL) throws -> [URL] {
        try collectUsageFiles(in: incomingFolder, recursive: false).sorted {
            (modificationDate(for: $0) ?? .distantPast) > (modificationDate(for: $1) ?? .distantPast)
        }
    }

    private static func collectUsageFiles(in directory: URL, recursive: Bool) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        let options: FileManager.DirectoryEnumerationOptions = recursive ? [] : [.skipsSubdirectoryDescendants]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys, options: options) else {
            return []
        }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent.lowercased()
            guard name.contains("deepseek") || name.contains("amount") || name.contains("cost") || name.contains("usage") || name.contains("export") else {
                continue
            }

            switch detectFileKind(at: fileURL) {
            case .zip, .csv:
                results.append(fileURL)
            case .unknown:
                continue
            }
        }

        return results
    }

    static func prepareManagedCSV(
        from source: URL,
        workspaceFolder: URL
    ) throws -> (amountURL: URL, costURL: URL?, selectedNames: [String]) {
        try clearManagedFolder(at: workspaceFolder)

        let kind = detectFileKind(at: source)
        guard kind != .unknown else {
            throw UsageCSVImportError.invalidExportArchive("文件不是有效的 ZIP 或 CSV")
        }
        if kind == .zip {
            let copiedZip = workspaceFolder.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: copiedZip)

            let extracted = workspaceFolder.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true, attributes: nil)
            try unzip(zipURL: copiedZip, into: extracted)

            let csvFiles = try collectUsageFiles(in: extracted, recursive: true).filter {
                $0.pathExtension.lowercased() == "csv"
            }

            let amountCSVs = csvFiles.filter {
                $0.lastPathComponent.lowercased().contains("amount")
            }
            let costCSVs = csvFiles.filter {
                $0.lastPathComponent.lowercased().contains("cost")
            }
            guard amountCSVs.count == 1, let amountCSV = amountCSVs.first else {
                throw UsageCSVImportError.invalidExportArchive("amount CSV 数量不正确")
            }
            guard costCSVs.count == 1, let costCSV = costCSVs.first else {
                throw UsageCSVImportError.invalidExportArchive("cost CSV 数量不正确")
            }

            let selectedNames = [amountCSV.lastPathComponent, costCSV.lastPathComponent]
            guard try exportDateRange(from: selectedNames) != nil else {
                throw UsageCSVImportError.invalidExportArchive("amount/cost 文件名缺少官方日期范围")
            }

            let amountDestination = workspaceFolder.appendingPathComponent("amount.csv")
            try FileManager.default.copyItem(at: amountCSV, to: amountDestination)

            let costDestination = workspaceFolder.appendingPathComponent("cost.csv")
            try FileManager.default.copyItem(at: costCSV, to: costDestination)

            let keptFiles = [amountDestination, costDestination]
            try clearManagedFolderKeeping(keptFiles, in: workspaceFolder)
            return (
                amountDestination,
                costDestination,
                selectedNames
            )
        }

        let destination = workspaceFolder.appendingPathComponent("amount.csv")
        try FileManager.default.copyItem(at: source, to: destination)
        try clearManagedFolderKeeping([destination], in: workspaceFolder)
        return (destination, nil, [source.lastPathComponent])
    }

    private static func cleanupCandidateFiles(in directory: URL, keeping keepURL: URL?) throws {
        let candidates = try collectUsageFiles(in: directory, recursive: false).sorted {
            (modificationDate(for: $0) ?? .distantPast) > (modificationDate(for: $1) ?? .distantPast)
        }

        let keepTarget: URL?
        if let keepURL,
           keepURL.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL {
            keepTarget = keepURL
        } else {
            keepTarget = candidates.first
        }

        for fileURL in candidates {
            if let keepTarget, fileURL.standardizedFileURL == keepTarget.standardizedFileURL {
                continue
            }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func parseExportDateRange(from fileName: String) -> ExportDateRange? {
        let name = URL(fileURLWithPath: fileName).lastPathComponent
        let pattern = #"(?:amount|cost)-(\d{4}-\d{2}-\d{2})_(\d{4}-\d{2}-\d{2})\.csv$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                in: name,
                range: NSRange(name.startIndex..<name.endIndex, in: name)
              ),
              let startRange = Range(match.range(at: 1), in: name),
              let endRange = Range(match.range(at: 2), in: name) else {
            return nil
        }
        return ExportDateRange(
            startDate: String(name[startRange]),
            endDateExclusive: String(name[endRange])
        )
    }

    private static func nextCalendarDate(after raw: String) -> String? {
        guard let date = UsageTime.day(from: raw),
              let nextDate = UsageTime.calendar(in: UsageTime.defaultTimeZone).date(
                  byAdding: .day,
                  value: 1,
                  to: date
              ) else {
            return nil
        }
        return UsageTime.formatter("yyyy-MM-dd").string(from: nextDate)
    }

    private static func clearManagedFolder(at url: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
    }

    private static func clearManagedFolderKeeping(_ keepURLs: [URL], in directory: URL) throws {
        let standardizedKeepURLs = Set(keepURLs.map(\.standardizedFileURL))
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for item in contents where standardizedKeepURLs.contains(item.standardizedFileURL) == false {
            try? FileManager.default.removeItem(at: item)
        }
    }

    private static func unzip(zipURL: URL, into destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destination.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UsageCSVImportError.unreadableFile
        }
    }

    private static func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func fileFingerprint(for url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values.fileSize ?? 0
        return "\(url.lastPathComponent)-\(modifiedAt)-\(fileSize)"
    }

    private enum DetectedFileKind {
        case zip
        case csv
        case unknown
    }

    private static func detectFileKind(at url: URL) -> DetectedFileKind {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .unknown
        }
        defer { try? handle.close() }

        let sample = (try? handle.read(upToCount: 512)) ?? Data()
        if isZIPArchive(sample) {
            return .zip
        }

        if let text = String(data: sample, encoding: .utf8)?.lowercased(),
           text.contains("utc_date") || text.contains("start_time_iso") ||
           text.contains("user_id") || text.contains("amount") {
            return .csv
        }

        return .unknown
    }

    private static func isZIPArchive(_ data: Data) -> Bool {
        let signatures: [[UInt8]] = [
            [0x50, 0x4B, 0x03, 0x04],
            [0x50, 0x4B, 0x05, 0x06],
            [0x50, 0x4B, 0x07, 0x08],
        ]
        return signatures.contains { data.starts(with: $0) }
    }
}
