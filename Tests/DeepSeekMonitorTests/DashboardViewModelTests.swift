import Foundation
import XCTest
@testable import DeepSeekMonitor

final class DashboardViewModelTests: XCTestCase {
    @MainActor
    func testInvalidCandidateKeyIsNotSaved() async throws {
        let environment = try makeEnvironment()
        defer { environment.cleanup() }

        let service = MockDeepSeekService(apiKey: "existing-key")
        service.validateError = APIError.unauthorized
        let viewModel = DashboardViewModel(
            service: service,
            cache: environment.cache,
            preferences: environment.preferences
        )

        do {
            _ = try await viewModel.validateAndSaveAPIKey("invalid-key")
            XCTFail("Expected candidate validation to fail")
        } catch {
            guard let apiError = error as? APIError,
                  case .unauthorized = apiError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(service.validateCallCount, 1)
        XCTAssertEqual(service.saveCallCount, 0)
        XCTAssertEqual(service.fetchBalanceCallCount, 0)
        XCTAssertEqual(service.apiKey, "existing-key")
        XCTAssertTrue(viewModel.hasAPIKey)
    }

    @MainActor
    func testValidCandidateKeyIsValidatedAndSavedExactlyOnce() async throws {
        let environment = try makeEnvironment()
        defer { environment.cleanup() }

        let service = MockDeepSeekService()
        let viewModel = DashboardViewModel(
            service: service,
            cache: environment.cache,
            preferences: environment.preferences
        )

        let response = try await viewModel.validateAndSaveAPIKey("  valid-key  ")

        XCTAssertEqual(response.balanceInfos.first?.totalBalance, "42.50")
        XCTAssertEqual(service.validateCallCount, 1)
        XCTAssertEqual(service.saveCallCount, 1)
        XCTAssertEqual(service.fetchBalanceCallCount, 0)
        XCTAssertEqual(service.apiKey, "valid-key")
        XCTAssertEqual(viewModel.apiKey, "valid-key")
        XCTAssertTrue(viewModel.hasAPIKey)
        XCTAssertEqual(viewModel.totalBalance, 42.50)
    }

    @MainActor
    func testUsage404TripsSessionCircuitBreaker() async throws {
        let environment = try makeEnvironment()
        defer { environment.cleanup() }

        let service = MockDeepSeekService(apiKey: "valid-key")
        service.usageError = APIError.usageEndpointUnavailable
        let viewModel = DashboardViewModel(
            service: service,
            cache: environment.cache,
            preferences: environment.preferences
        )

        await viewModel.refresh()
        await viewModel.refresh()

        XCTAssertEqual(service.fetchBalanceCallCount, 2)
        XCTAssertEqual(service.fetchUsageCallCount, 1)
        XCTAssertEqual(
            viewModel.usageDataState,
            .unavailable(APIError.usageEndpointUnavailable.errorDescription ?? "")
        )
        XCTAssertTrue(viewModel.isUsageUnavailable)
    }

    @MainActor
    func testRefreshIntervalPersistsAcrossViewModelInstances() throws {
        let environment = try makeEnvironment()
        defer { environment.cleanup() }

        let service = MockDeepSeekService()
        let first = DashboardViewModel(
            service: service,
            cache: environment.cache,
            preferences: environment.preferences
        )
        first.refreshInterval = 120

        let second = DashboardViewModel(
            service: service,
            cache: environment.cache,
            preferences: environment.preferences
        )

        XCTAssertEqual(environment.preferences.double(forKey: "balance_refresh_interval_seconds"), 120)
        XCTAssertEqual(second.refreshInterval, 120)
    }

    @MainActor
    func testClearCacheRemovesWidgetSnapshotButKeepsKeyAndSettings() throws {
        let environment = try makeEnvironment(includeSharedDefaults: true)
        defer { environment.cleanup() }
        let sharedDefaults = try XCTUnwrap(environment.sharedDefaults)

        environment.preferences.set(120, forKey: "balance_refresh_interval_seconds")
        environment.cache.setNativeWidgetEnabled(false)
        environment.cache.saveDashboard(makeDashboardCache())
        XCTAssertNotNil(sharedDefaults.data(forKey: "widget_snapshot"))

        let service = MockDeepSeekService(apiKey: "valid-key")
        let viewModel = DashboardViewModel(
            service: service,
            cache: environment.cache,
            preferences: environment.preferences
        )

        viewModel.clearCachedData()

        XCTAssertEqual(service.clearCallCount, 0)
        XCTAssertEqual(service.apiKey, "valid-key")
        XCTAssertTrue(viewModel.hasAPIKey)
        XCTAssertEqual(environment.preferences.double(forKey: "balance_refresh_interval_seconds"), 120)
        XCTAssertFalse(sharedDefaults.bool(forKey: "native_widget_enabled"))
        XCTAssertNil(sharedDefaults.data(forKey: "widget_snapshot"))
        XCTAssertNil(environment.cache.loadDashboard())
        XCTAssertTrue(environment.cache.loadUsageRecords().isEmpty)
    }

    @MainActor
    func testDuplicateAutomaticDownloadIsRejectedBeforeParsing() throws {
        let environment = try makeEnvironment()
        defer { environment.cleanup() }
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("duplicate-export.zip")
        try Data("already imported".utf8).write(to: fileURL)

        let service = MockDeepSeekService()
        let viewModel = DashboardViewModel(
            service: service,
            cache: environment.cache,
            preferences: environment.preferences
        )
        let fingerprint = try UsageAutoImportService.importFingerprint(for: fileURL)
        UsageAutoImportService.markImported(
            fingerprint,
            defaults: environment.preferences
        )

        let result = viewModel.importAutomaticUsageExport(
            UsageExportDownloadEvent(
                taskID: UUID(),
                fileURL: fileURL,
                referenceDate: Date()
            )
        )

        guard case .noNewFile = result else {
            return XCTFail("Expected the duplicate event to be ignored")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testFailedImportIsMovedIntoQuarantine() throws {
        let directory = try makeTemporaryDirectory()
        let incoming = directory.appendingPathComponent("incoming", isDirectory: true)
        let failed = directory.appendingPathComponent("failed", isDirectory: true)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        let source = incoming.appendingPathComponent("usage-export.zip")
        try Data("invalid archive".utf8).write(to: source)

        let destination = try UsageAutoImportService.quarantineFailedImport(
            source,
            failedFolder: failed
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(destination.deletingLastPathComponent().standardizedFileURL, failed.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: destination), Data("invalid archive".utf8))
    }

    private func makeEnvironment(includeSharedDefaults: Bool = false) throws -> TestEnvironment {
        let preferencesName = "DashboardViewModelTests.preferences.\(UUID().uuidString)"
        let cacheName = "DashboardViewModelTests.cache.\(UUID().uuidString)"
        let sharedName = "DashboardViewModelTests.shared.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: preferencesName))
        let cacheDefaults = try XCTUnwrap(UserDefaults(suiteName: cacheName))
        let sharedDefaults = includeSharedDefaults
            ? try XCTUnwrap(UserDefaults(suiteName: sharedName))
            : nil
        preferences.removePersistentDomain(forName: preferencesName)
        cacheDefaults.removePersistentDomain(forName: cacheName)
        sharedDefaults?.removePersistentDomain(forName: sharedName)

        return TestEnvironment(
            preferencesName: preferencesName,
            cacheName: cacheName,
            sharedName: includeSharedDefaults ? sharedName : nil,
            preferences: preferences,
            cacheDefaults: cacheDefaults,
            sharedDefaults: sharedDefaults
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func makeDashboardCache() -> DashboardCache {
        DashboardCache(
            isAccountAvailable: true,
            totalBalance: 42.50,
            grantedBalance: 2.50,
            toppedUpBalance: 40,
            balanceCurrencyCode: "CNY",
            usageCurrencyCode: "CNY",
            currentDayCost: 1,
            currentMonthCost: 10,
            flashTotalTokens: 100,
            flashCostInCents: 10,
            proTotalTokens: 200,
            proCostInCents: 20,
            dailyUsage: ["2026-08-14": 300],
            balanceLastUpdated: Date(),
            usageLastUpdated: Date(),
            lastUpdated: Date()
        )
    }
}

private struct TestEnvironment {
    let preferencesName: String
    let cacheName: String
    let sharedName: String?
    let preferences: UserDefaults
    let cacheDefaults: UserDefaults
    let sharedDefaults: UserDefaults?

    var cache: LocalCache {
        LocalCache(defaults: cacheDefaults, sharedDefaults: sharedDefaults)
    }

    func cleanup() {
        preferences.removePersistentDomain(forName: preferencesName)
        cacheDefaults.removePersistentDomain(forName: cacheName)
        if let sharedName {
            sharedDefaults?.removePersistentDomain(forName: sharedName)
        }
    }
}

private final class MockDeepSeekService: DeepSeekServicing {
    var apiKey: String?
    var apiKeyStorageWarning: String?
    var validateError: Error?
    var saveError: Error?
    var balanceError: Error?
    var usageError: Error?
    var balanceResponse = BalanceResponse(
        isAvailable: true,
        balanceInfos: [
            BalanceInfo(
                currency: "CNY",
                totalBalance: "42.50",
                grantedBalance: "2.50",
                toppedUpBalance: "40.00"
            )
        ]
    )
    var usageResponse = UsageResponse(data: [])
    private(set) var validateCallCount = 0
    private(set) var saveCallCount = 0
    private(set) var clearCallCount = 0
    private(set) var fetchBalanceCallCount = 0
    private(set) var fetchUsageCallCount = 0

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    var hasAPIKey: Bool {
        (apiKey ?? "").isEmpty == false
    }

    func saveAPIKey(_ apiKey: String) throws {
        saveCallCount += 1
        if let saveError { throw saveError }
        self.apiKey = apiKey
    }

    func clearAPIKey() throws {
        clearCallCount += 1
        apiKey = nil
    }

    func fetchBalance() async throws -> BalanceResponse {
        fetchBalanceCallCount += 1
        if let balanceError { throw balanceError }
        return balanceResponse
    }

    func validateAPIKey(_ apiKey: String) async throws -> BalanceResponse {
        validateCallCount += 1
        if let validateError { throw validateError }
        return balanceResponse
    }

    func fetchRecentUsage(days: Int) async throws -> UsageResponse {
        fetchUsageCallCount += 1
        if let usageError { throw usageError }
        return usageResponse
    }
}
