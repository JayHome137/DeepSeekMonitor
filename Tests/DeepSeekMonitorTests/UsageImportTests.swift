import Foundation
import XCTest
@testable import DeepSeekMonitor

final class UsageImportTests: XCTestCase {
    func testAmountAndCostExportsMergeExactUSDWithQuotedAPIKeyName() throws {
        let directory = try makeTemporaryDirectory()
        let amountURL = try write(
            """
            api_key_name,utc_date,model,type,price,amount
            "Team, Primary",2026-07-24,deepseek-v4-flash,input_cache_hit_tokens,0.000001,1000
            "Team, Primary",2026-07-24,deepseek-v4-flash,input_cache_miss_tokens,0.000002,500
            "Team, Primary",2026-07-24,deepseek-v4-flash,output_tokens,0.000004,200
            "Team, Primary",2026-07-24,deepseek-v4-flash,request_count,0,3
            """,
            named: "amount.csv",
            in: directory
        )
        let costURL = try write(
            """
            api_key_name,utc_date,model,currency,wallet_type,cost
            "Team, Primary",2026-07-24,deepseek-v4-flash,USD,paid,0.0049
            "Team, Primary",2026-07-24,deepseek-v4-flash,USD,granted,0.0052
            """,
            named: "cost.csv",
            in: directory
        )

        let records = try UsageCSVImporter.importRecords(from: amountURL, costURL: costURL)
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.totalTokens, 1_700)
        XCTAssertEqual(record.promptTokens, 1_500)
        XCTAssertEqual(record.inputCacheHitTokens, 1_000)
        XCTAssertEqual(record.inputCacheMissTokens, 500)
        XCTAssertEqual(record.completionTokens, 200)
        XCTAssertEqual(record.requestCount, 3)
        XCTAssertEqual(record.costAmount(for: "USD"), decimal("0.0101"))
        XCTAssertEqual(record.costAmount(for: "CNY"), .zero)
    }

    func testAmountRowsKeepSubCentPrecisionUntilAfterAggregation() throws {
        let directory = try makeTemporaryDirectory()
        let amountURL = try write(
            """
            api_key_name,utc_date,model,type,price,amount
            test,2026-07-24,deepseek-v4-pro,input_cache_hit_tokens,0.004,1
            test,2026-07-24,deepseek-v4-pro,output_tokens,0.004,1
            """,
            named: "amount.csv",
            in: directory
        )

        let record = try XCTUnwrap(
            UsageCSVImporter.importRecords(
                from: amountURL,
                defaultCurrencyCode: "USD"
            ).first
        )

        XCTAssertEqual(record.costAmount(for: "USD"), decimal("0.008"))
        XCTAssertEqual(record.costAmount(for: "CNY"), .zero)
        XCTAssertEqual(record.costInCents(for: "USD"), 1)
    }

    func testCostExportKeepsCurrenciesSeparate() throws {
        let directory = try makeTemporaryDirectory()
        let amountURL = try write(
            """
            api_key_name,utc_date,model,type,price,amount
            test,2026-07-24,deepseek-v4-pro,output_tokens,0,1
            """,
            named: "amount.csv",
            in: directory
        )
        let costURL = try write(
            """
            api_key_name,utc_date,model,currency,wallet_type,cost
            test,2026-07-24,deepseek-v4-pro,CNY,paid,0.50
            test,2026-07-24,deepseek-v4-pro,USD,paid,0.10
            """,
            named: "cost.csv",
            in: directory
        )

        let record = try XCTUnwrap(UsageCSVImporter.importRecords(from: amountURL, costURL: costURL).first)

        XCTAssertEqual(record.costAmount(for: "CNY"), decimal("0.50"))
        XCTAssertEqual(record.costAmount(for: "USD"), decimal("0.10"))
        XCTAssertEqual(record.costAmount(for: "JPY"), .zero)
    }

    func testUsageDateComparisonAlwaysUsesUTC() throws {
        let formatter = ISO8601DateFormatter()
        let reference = try XCTUnwrap(formatter.date(from: "2026-06-30T16:30:00Z"))

        XCTAssertTrue(UsageTime.isSameDay("2026-06-30", as: reference))
        XCTAssertFalse(UsageTime.isSameDay("2026-07-01", as: reference))
        XCTAssertTrue(UsageTime.isSameMonth("2026-06-01", as: reference))
        XCTAssertFalse(UsageTime.isSameMonth("2026-07-01", as: reference))
    }

    func testOfficialZIPPreparesAmountAndCostFilesTogether() throws {
        let directory = try makeTemporaryDirectory()
        let exportDirectory = directory.appendingPathComponent("export", isDirectory: true)
        let workspaceDirectory = directory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)

        _ = try write(
            """
            api_key_name,utc_date,model,type,price,amount
            test,2026-07-24,deepseek-v4-flash,output_tokens,0.001,2
            """,
            named: "amount-20260724.csv",
            in: exportDirectory
        )
        _ = try write(
            """
            api_key_name,utc_date,model,currency,wallet_type,cost
            test,2026-07-24,deepseek-v4-flash,USD,paid,0.25
            """,
            named: "cost-20260724.csv",
            in: exportDirectory
        )

        let zipURL = directory.appendingPathComponent("deepseek-usage.zip")
        try createZIP(from: exportDirectory, at: zipURL)
        let prepared = try UsageAutoImportService.prepareManagedCSV(
            from: zipURL,
            workspaceFolder: workspaceDirectory
        )
        let costURL = try XCTUnwrap(prepared.costURL)
        let record = try XCTUnwrap(
            UsageCSVImporter.importRecords(from: prepared.amountURL, costURL: costURL).first
        )

        XCTAssertEqual(Set(prepared.selectedNames), ["amount-20260724.csv", "cost-20260724.csv"])
        XCTAssertEqual(record.totalTokens, 2)
        XCTAssertEqual(record.costAmount(for: "USD"), decimal("0.25"))
    }

    func testLegacyUsageRecordDecodingDefaultsToCNY() throws {
        let json = """
        {
          "id": "legacy",
          "model_name": "deepseek-v4-flash",
          "total_tokens": 10,
          "prompt_tokens": 7,
          "input_cache_hit_tokens": 2,
          "input_cache_miss_tokens": 5,
          "completion_tokens": 3,
          "cost_in_cents": 7,
          "date": "2026-07-24",
          "request_count": 1
        }
        """

        let record = try JSONDecoder().decode(UsageRecord.self, from: Data(json.utf8))

        XCTAssertEqual(record.costAmount(for: "CNY"), decimal("0.07"))
        XCTAssertEqual(record.primaryCurrencyCode, "CNY")
    }

    func testLegacyDashboardCacheDecodingBackfillsCurrencyAndUpdateTimes() throws {
        let lastUpdated = Date(timeIntervalSinceReferenceDate: 123_456)
        let legacy = LegacyDashboardCache(lastUpdated: lastUpdated)
        let data = try JSONEncoder().encode(legacy)

        let cache = try JSONDecoder().decode(DashboardCache.self, from: data)

        XCTAssertEqual(cache.balanceCurrencyCode, "CNY")
        XCTAssertEqual(cache.usageCurrencyCode, "CNY")
        XCTAssertEqual(cache.balanceLastUpdated, lastUpdated)
        XCTAssertEqual(cache.usageLastUpdated, lastUpdated)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepSeekMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func write(_ contents: String, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func createZIP(from directory: URL, at destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", directory.path, destination.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}

private struct LegacyDashboardCache: Encodable {
    let isAccountAvailable = true
    let totalBalance = 10.0
    let grantedBalance = 2.0
    let toppedUpBalance = 8.0
    let currentDayCost = 1.0
    let currentMonthCost = 3.0
    let flashTotalTokens = 100
    let flashCostInCents = 10
    let proTotalTokens = 200
    let proCostInCents = 20
    let dailyUsage = ["2026-07-24": 300]
    let lastUpdated: Date
}
