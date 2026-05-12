import Foundation

enum UsageAutoImportService {
    private static let fingerprintKey = "auto_import_usage_fingerprint_v2"
    private static let rootFolderName = "usage-sync"
    private static let incomingFolderName = "incoming"
    private static let workspaceFolderName = "workspace"

    struct ImportCandidate {
        let sourceURL: URL
        let preparedCSVURL: URL
        let fingerprint: String
        let sourceName: String
        let selectedCSVName: String
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

    static func watchedFolderURLs() throws -> [URL] {
        [try incomingFolderURL()]
    }

    static func nextImportCandidate() throws -> ImportCandidate? {
        let incomingFolder = try incomingFolderURL()
        let workspaceFolder = try autoImportFolderURL()
        let candidates = try sourceCandidates(incomingFolder: incomingFolder)
        guard let latest = candidates.first else { return nil }

        let fingerprint = try fileFingerprint(for: latest)
        let defaults = UserDefaults.standard
        if defaults.string(forKey: fingerprintKey) == fingerprint {
            return nil
        }

        let prepared = try prepareManagedCSV(from: latest, workspaceFolder: workspaceFolder)
        return ImportCandidate(
            sourceURL: latest,
            preparedCSVURL: prepared.url,
            fingerprint: fingerprint,
            sourceName: latest.lastPathComponent,
            selectedCSVName: prepared.selectedName
        )
    }

    static func markImported(_ fingerprint: String) {
        UserDefaults.standard.set(fingerprint, forKey: fingerprintKey)
    }

    static func cleanupImportedSources(keeping keepURL: URL?) throws {
        let incomingFolder = try incomingFolderURL()
        try cleanupCandidateFiles(in: incomingFolder, keeping: keepURL)
    }

    static func resetRememberedImport() {
        UserDefaults.standard.removeObject(forKey: fingerprintKey)
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
            guard name.contains("deepseek") || name.contains("amount") || name.contains("usage") || name.contains("export") else {
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

    private static func prepareManagedCSV(from source: URL, workspaceFolder: URL) throws -> (url: URL, selectedName: String) {
        try clearManagedFolder(at: workspaceFolder)

        let kind = detectFileKind(at: source)
        if kind == .zip {
            let copiedZip = workspaceFolder.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: copiedZip)

            let extracted = workspaceFolder.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true, attributes: nil)
            try unzip(zipURL: copiedZip, into: extracted)

            let csvFiles = try collectUsageFiles(in: extracted, recursive: true).filter {
                $0.pathExtension.lowercased() == "csv"
            }

            guard let amountCSV = preferredCSV(from: csvFiles) else {
                throw UsageCSVImportError.noValidRows
            }

            let destination = workspaceFolder.appendingPathComponent("amount.csv")
            try FileManager.default.copyItem(at: amountCSV, to: destination)
            try clearManagedFolderKeeping(destination, in: workspaceFolder)
            return (destination, amountCSV.lastPathComponent)
        }

        let destination = workspaceFolder.appendingPathComponent("amount.csv")
        try FileManager.default.copyItem(at: source, to: destination)
        try clearManagedFolderKeeping(destination, in: workspaceFolder)
        return (destination, source.lastPathComponent)
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

    private static func preferredCSV(from files: [URL]) -> URL? {
        let sorted = files.sorted {
            (modificationDate(for: $0) ?? .distantPast) > (modificationDate(for: $1) ?? .distantPast)
        }

        return sorted.first { $0.lastPathComponent.lowercased().contains("amount") } ?? sorted.first
    }

    private static func clearManagedFolder(at url: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
    }

    private static func clearManagedFolderKeeping(_ keepURL: URL, in directory: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for item in contents where item != keepURL {
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
        let ext = url.pathExtension.lowercased()
        if ext == "zip" { return .zip }
        if ext == "csv" { return .csv }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .unknown
        }
        defer { try? handle.close() }

        let sample = (try? handle.read(upToCount: 256)) ?? Data()
        if sample.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            return .zip
        }

        if let text = String(data: sample, encoding: .utf8)?.lowercased(),
           text.contains("utc_date") || text.contains("user_id") || text.contains("amount") {
            return .csv
        }

        return .unknown
    }
}
