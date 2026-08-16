import Foundation

enum UsageAutoImportService {
    private static let fingerprintKey = "auto_import_usage_fingerprint_v2"
    private static let rootFolderName = "usage-sync"
    private static let incomingFolderName = "incoming"
    private static let failedFolderName = "failed"
    private static let workspaceFolderName = "workspace"
    static let maximumArchiveByteCount = 64 * 1024 * 1024
    private static let maximumArchiveEntryCount = 64
    private static let maximumArchivePathByteCount = 1_024
    private static let maximumExtractedFileByteCount = 128 * 1024 * 1024
    private static let maximumExtractedTotalByteCount = 256 * 1024 * 1024

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
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
        ]
        let options: FileManager.DirectoryEnumerationOptions = recursive ? [] : [.skipsSubdirectoryDescendants]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys, options: options) else {
            return []
        }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                continue
            }
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
            try validateRegularFile(at: source, maximumByteCount: maximumArchiveByteCount)
            let copiedZip = workspaceFolder.appendingPathComponent("archive.zip")
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
            try validateExtractedFile(amountCSV, inside: extracted)
            try validateExtractedFile(costCSV, inside: extracted)

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

        try validateRegularFile(at: source, maximumByteCount: maximumExtractedFileByteCount)
        let destination = workspaceFolder.appendingPathComponent("amount.csv")
        try FileManager.default.copyItem(at: source, to: destination)
        try validateRegularFile(at: destination, maximumByteCount: maximumExtractedFileByteCount)
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
        try validateZIPArchive(at: zipURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destination.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UsageCSVImportError.unreadableFile
        }

        try validateExtractedContents(in: destination)
    }

    static func validateZIPArchive(at zipURL: URL) throws {
        try validateRegularFile(at: zipURL, maximumByteCount: maximumArchiveByteCount)

        let archiveData: Data
        do {
            archiveData = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        } catch {
            throw UsageCSVImportError.unreadableFile
        }

        guard isZIPArchive(archiveData),
              let eocdOffset = endOfCentralDirectoryOffset(in: archiveData),
              let diskNumber = archiveData.zipUInt16(at: eocdOffset + 4),
              let centralDirectoryDisk = archiveData.zipUInt16(at: eocdOffset + 6),
              let entriesOnDisk = archiveData.zipUInt16(at: eocdOffset + 8),
              let totalEntries = archiveData.zipUInt16(at: eocdOffset + 10),
              let centralDirectorySize = archiveData.zipUInt32(at: eocdOffset + 12),
              let centralDirectoryOffset = archiveData.zipUInt32(at: eocdOffset + 16),
              diskNumber == 0,
              centralDirectoryDisk == 0,
              entriesOnDisk == totalEntries,
              totalEntries > 0,
              totalEntries != UInt16.max,
              centralDirectorySize != UInt32.max,
              centralDirectoryOffset != UInt32.max,
              Int(totalEntries) <= maximumArchiveEntryCount else {
            throw UsageCSVImportError.invalidExportArchive("ZIP 中央目录无效或条目过多")
        }

        let centralStart = Int(centralDirectoryOffset)
        let centralSize = Int(centralDirectorySize)
        guard centralStart >= 0,
              centralSize >= 0,
              centralStart <= eocdOffset,
              centralSize <= eocdOffset - centralStart else {
            throw UsageCSVImportError.invalidExportArchive("ZIP 中央目录越界")
        }

        let centralEnd = centralStart + centralSize
        var cursor = centralStart
        var normalizedPaths = Set<String>()
        var localHeaderOffsets = Set<Int>()
        var totalUncompressedBytes: UInt64 = 0
        var regularFileCount = 0

        for _ in 0..<Int(totalEntries) {
            guard cursor <= centralEnd - 46,
                  archiveData.zipUInt32(at: cursor) == 0x02014B50,
                  let versionMadeBy = archiveData.zipUInt16(at: cursor + 4),
                  let flags = archiveData.zipUInt16(at: cursor + 8),
                  let compressionMethod = archiveData.zipUInt16(at: cursor + 10),
                  let compressedSize = archiveData.zipUInt32(at: cursor + 20),
                  let uncompressedSize = archiveData.zipUInt32(at: cursor + 24),
                  let fileNameLength = archiveData.zipUInt16(at: cursor + 28),
                  let extraLength = archiveData.zipUInt16(at: cursor + 30),
                  let commentLength = archiveData.zipUInt16(at: cursor + 32),
                  let externalAttributes = archiveData.zipUInt32(at: cursor + 38),
                  let localHeaderOffsetValue = archiveData.zipUInt32(at: cursor + 42),
                  compressedSize != UInt32.max,
                  uncompressedSize != UInt32.max,
                  localHeaderOffsetValue != UInt32.max,
                  flags & 0x0001 == 0,
                  compressionMethod == 0 || compressionMethod == 8 else {
                throw UsageCSVImportError.invalidExportArchive("ZIP 条目格式不受支持")
            }

            let nameLength = Int(fileNameLength)
            let nextCursor = cursor + 46 + nameLength + Int(extraLength) + Int(commentLength)
            guard nameLength > 0,
                  nameLength <= maximumArchivePathByteCount,
                  nextCursor <= centralEnd else {
                throw UsageCSVImportError.invalidExportArchive("ZIP 条目名称或长度无效")
            }

            let fileNameData = Data(archiveData[(cursor + 46)..<(cursor + 46 + nameLength)])
            guard fileNameData.contains(0) == false,
                  let fileName = String(data: fileNameData, encoding: .utf8) else {
                throw UsageCSVImportError.invalidExportArchive("ZIP 条目名称编码无效")
            }

            let unixFileType = UInt16((externalAttributes >> 16) & 0o170000)
            let creatorSystem = UInt8((versionMadeBy >> 8) & 0xFF)
            if creatorSystem == 3,
               unixFileType != 0,
               unixFileType != 0o040000,
               unixFileType != 0o100000 {
                throw UsageCSVImportError.invalidExportArchive("ZIP 包含符号链接或特殊文件")
            }

            let normalizedPath = try normalizedArchivePath(fileName)
            guard normalizedPaths.insert(normalizedPath.key).inserted else {
                throw UsageCSVImportError.invalidExportArchive("ZIP 包含重复路径")
            }

            let isDirectory = normalizedPath.isDirectory ||
                unixFileType == 0o040000 ||
                externalAttributes & 0x10 != 0
            if isDirectory {
                guard uncompressedSize == 0 else {
                    throw UsageCSVImportError.invalidExportArchive("ZIP 目录条目大小无效")
                }
            } else {
                regularFileCount += 1
                guard UInt64(uncompressedSize) <= UInt64(maximumExtractedFileByteCount) else {
                    throw UsageCSVImportError.invalidExportArchive("ZIP 单个文件超过安全上限")
                }
                totalUncompressedBytes += UInt64(uncompressedSize)
                guard totalUncompressedBytes <= UInt64(maximumExtractedTotalByteCount) else {
                    throw UsageCSVImportError.invalidExportArchive("ZIP 解压总量超过安全上限")
                }
            }

            let localHeaderOffset = Int(localHeaderOffsetValue)
            guard localHeaderOffsets.insert(localHeaderOffset).inserted,
                  localHeaderOffset >= 0,
                  localHeaderOffset <= centralStart - 30,
                  archiveData.zipUInt32(at: localHeaderOffset) == 0x04034B50,
                  archiveData.zipUInt16(at: localHeaderOffset + 6) == flags,
                  archiveData.zipUInt16(at: localHeaderOffset + 8) == compressionMethod,
                  let localNameLength = archiveData.zipUInt16(at: localHeaderOffset + 26),
                  let localExtraLength = archiveData.zipUInt16(at: localHeaderOffset + 28) else {
                throw UsageCSVImportError.invalidExportArchive("ZIP 本地文件头无效")
            }

            let localDataStart = localHeaderOffset + 30 + Int(localNameLength) + Int(localExtraLength)
            guard localDataStart <= centralStart,
                  UInt64(localDataStart) + UInt64(compressedSize) <= UInt64(centralStart),
                  Int(localNameLength) == nameLength,
                  Data(archiveData[(localHeaderOffset + 30)..<(localHeaderOffset + 30 + nameLength)]) == fileNameData else {
                throw UsageCSVImportError.invalidExportArchive("ZIP 文件内容边界无效")
            }

            cursor = nextCursor
        }

        guard cursor == centralEnd, regularFileCount > 0 else {
            throw UsageCSVImportError.invalidExportArchive("ZIP 中央目录不完整")
        }
    }

    private static func endOfCentralDirectoryOffset(in data: Data) -> Int? {
        let recordLength = 22
        let maximumCommentLength = 65_535
        guard data.count >= recordLength else { return nil }

        let lowerBound = max(0, data.count - recordLength - maximumCommentLength)
        for offset in stride(from: data.count - recordLength, through: lowerBound, by: -1) {
            guard data.zipUInt32(at: offset) == 0x06054B50,
                  let commentLength = data.zipUInt16(at: offset + 20),
                  offset + recordLength + Int(commentLength) == data.count else {
                continue
            }
            return offset
        }
        return nil
    }

    private static func normalizedArchivePath(_ rawPath: String) throws -> (key: String, isDirectory: Bool) {
        guard rawPath.utf8.count <= maximumArchivePathByteCount,
              rawPath.contains("\\") == false,
              rawPath.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else {
            throw UsageCSVImportError.invalidExportArchive("ZIP 包含无效路径")
        }

        let path = rawPath
        let isDirectory = path.hasSuffix("/")
        guard path.hasPrefix("/") == false,
              path.contains(":") == false else {
            throw UsageCSVImportError.invalidExportArchive("ZIP 包含绝对路径")
        }

        var components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if isDirectory, components.last == "" {
            components.removeLast()
        }
        guard components.isEmpty == false,
              components.count <= 16,
              components.allSatisfy({ $0.isEmpty == false && $0 != "." && $0 != ".." }) else {
            throw UsageCSVImportError.invalidExportArchive("ZIP 包含越界路径")
        }

        return (components.joined(separator: "/").lowercased(), isDirectory)
    }

    private static func validateExtractedContents(in directory: URL) throws {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys)
        ) else {
            throw UsageCSVImportError.unreadableFile
        }

        let resolvedRoot = directory.resolvingSymlinksInPath().standardizedFileURL
        var fileCount = 0
        var totalByteCount = 0
        for case let itemURL as URL in enumerator {
            let values = try itemURL.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true,
                  isContained(itemURL.resolvingSymlinksInPath(), in: resolvedRoot) else {
                throw UsageCSVImportError.invalidExportArchive("ZIP 解压结果包含越界链接")
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize >= 0,
                  fileSize <= maximumExtractedFileByteCount else {
                throw UsageCSVImportError.invalidExportArchive("ZIP 解压结果包含异常文件")
            }

            fileCount += 1
            totalByteCount += fileSize
            guard fileCount <= maximumArchiveEntryCount,
                  totalByteCount <= maximumExtractedTotalByteCount else {
                throw UsageCSVImportError.invalidExportArchive("ZIP 解压结果超过安全上限")
            }
        }
    }

    private static func validateExtractedFile(_ fileURL: URL, inside root: URL) throws {
        try validateRegularFile(at: fileURL, maximumByteCount: maximumExtractedFileByteCount)
        guard isContained(fileURL.resolvingSymlinksInPath(), in: root.resolvingSymlinksInPath()) else {
            throw UsageCSVImportError.invalidExportArchive("CSV 路径超出解压目录")
        }
    }

    private static func validateRegularFile(at url: URL, maximumByteCount: Int) throws {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize >= 0,
              fileSize <= maximumByteCount else {
            throw UsageCSVImportError.invalidExportArchive("文件类型或大小不符合安全要求")
        }
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
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
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            return .unknown
        }
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

private extension Data {
    func zipUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset <= count - 2 else { return nil }
        return UInt16(self[offset]) |
            (UInt16(self[offset + 1]) << 8)
    }

    func zipUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= count - 4 else { return nil }
        return UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }
}
