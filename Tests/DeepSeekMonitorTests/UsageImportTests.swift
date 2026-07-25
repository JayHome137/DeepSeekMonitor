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

    func testOfficialCRLFExportsWithBOMAndCompactDatesImportSuccessfully() throws {
        let directory = try makeTemporaryDirectory()
        let amountLines = [
            "user_id,utc_date,model,api_key_name,api_key,type,price,amount",
            "account,20260725,deepseek-v4-pro,\"Team, Primary\",sk-masked,input_cache_hit_tokens,0.000000025,1000",
            "account,20260725,deepseek-v4-pro,\"Team, Primary\",sk-masked,input_cache_miss_tokens,0.000003,500",
            "account,20260725,deepseek-v4-pro,\"Team, Primary\",sk-masked,output_tokens,0.000006,200",
            "account,20260725,deepseek-v4-pro,\"Team, Primary\",sk-masked,request_count,,3",
        ]
        let costLines = [
            "user_id,utc_date,model,wallet_type,cost,currency",
            "account,20260725,deepseek-v4-pro,paid,1.2345,CNY",
        ]

        var amountData = Data([0xEF, 0xBB, 0xBF])
        amountData.append(Data((amountLines.joined(separator: "\r\n") + "\r\n").utf8))
        var costData = Data([0xEF, 0xBB, 0xBF])
        costData.append(Data((costLines.joined(separator: "\r\n") + "\r\n").utf8))

        let amountURL = try write(amountData, named: "amount-2026-07-25_2026-07-26.csv", in: directory)
        let costURL = try write(costData, named: "cost-2026-07-25_2026-07-26.csv", in: directory)
        let record = try XCTUnwrap(
            UsageCSVImporter.importRecords(from: amountURL, costURL: costURL).first
        )

        XCTAssertEqual(record.date, "2026-07-25")
        XCTAssertEqual(record.modelName, DeepSeekModel.pro.rawValue)
        XCTAssertEqual(record.totalTokens, 1_700)
        XCTAssertEqual(record.inputCacheHitTokens, 1_000)
        XCTAssertEqual(record.inputCacheMissTokens, 500)
        XCTAssertEqual(record.completionTokens, 200)
        XCTAssertEqual(record.requestCount, 3)
        XCTAssertEqual(record.costAmount(for: "CNY"), decimal("1.2345"))
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
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        XCTAssertTrue(UsageTime.isSameDay("2026-06-30", as: reference, timeZone: utc))
        XCTAssertFalse(UsageTime.isSameDay("2026-07-01", as: reference, timeZone: utc))
        XCTAssertTrue(UsageTime.isSameMonth("2026-06-01", as: reference, timeZone: utc))
        XCTAssertFalse(UsageTime.isSameMonth("2026-07-01", as: reference, timeZone: utc))
    }

    func testUsageDateComparisonSupportsChinaNaturalDay() throws {
        let formatter = ISO8601DateFormatter()
        let reference = try XCTUnwrap(formatter.date(from: "2026-07-24T16:30:00Z"))
        let china = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3_600))

        XCTAssertTrue(UsageTime.isSameDay("2026-07-25", as: reference, timeZone: china))
        XCTAssertFalse(UsageTime.isSameDay("2026-07-24", as: reference, timeZone: china))
        XCTAssertEqual(UsageTime.offsetLabel(seconds: 8 * 3_600), "UTC+08:00")
    }

    func testTimestampRowsAreGroupedIntoTheExportTimeZoneDay() throws {
        let directory = try makeTemporaryDirectory()
        let amountURL = try write(
            """
            date,model,total_tokens,amount,currency
            2026-07-24T16:30:00Z,deepseek-v4-pro,1,0.1,CNY
            """,
            named: "usage.csv",
            in: directory
        )
        let china = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3_600))

        let record = try XCTUnwrap(
            UsageCSVImporter.importRecords(
                from: amountURL,
                dataTimeZone: china
            ).first
        )

        XCTAssertEqual(record.date, "2026-07-25")
    }

    func testUsageExportRequestUses31LocalDaysAndSelectedOffset() throws {
        let formatter = ISO8601DateFormatter()
        let reference = try XCTUnwrap(formatter.date(from: "2026-07-25T13:30:00Z"))
        let expectedStart = try XCTUnwrap(formatter.date(from: "2026-06-24T16:00:00Z"))
        let expectedEnd = try XCTUnwrap(formatter.date(from: "2026-07-25T16:00:00Z"))
        let china = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3_600))

        let configuration = UsageExportRequestConfiguration.make(
            referenceDate: reference,
            timeZone: china
        )

        XCTAssertEqual(configuration.startSeconds, Int(expectedStart.timeIntervalSince1970))
        XCTAssertEqual(configuration.endSeconds, Int(expectedEnd.timeIntervalSince1970))
        XCTAssertEqual(configuration.timeZoneOffsetSeconds, 28_800)
        XCTAssertEqual(configuration.startDate, "2026-06-25")
        XCTAssertEqual(configuration.endDateExclusive, "2026-07-26")
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

    func testOfficialExportRangeRejectsStaleAutomaticImport() throws {
        let fileNames = [
            "amount-2026-07-01_2026-07-26.csv",
            "cost-2026-07-01_2026-07-26.csv",
        ]
        let range = try XCTUnwrap(UsageAutoImportService.exportDateRange(from: fileNames))
        let placeholder = URL(fileURLWithPath: "/tmp/usage-export.zip")
        let candidate = UsageAutoImportService.ImportCandidate(
            sourceURL: placeholder,
            preparedAmountCSVURL: placeholder,
            preparedCostCSVURL: nil,
            fingerprint: "test",
            sourceName: placeholder.lastPathComponent,
            selectedCSVNames: fileNames,
            exportDateRange: range
        )

        XCTAssertTrue(range.contains("2026-07-25"))
        XCTAssertNoThrow(
            try UsageAutoImportService.validateCurrentExport(candidate, expectedDate: "2026-07-25")
        )
        XCTAssertThrowsError(
            try UsageAutoImportService.validateCurrentExport(candidate, expectedDate: "2026-07-26")
        ) { error in
            guard case UsageCSVImportError.staleExportRange(
                let startDate,
                let endDateExclusive,
                let expectedDate
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(startDate, "2026-07-01")
            XCTAssertEqual(endDateExclusive, "2026-07-26")
            XCTAssertEqual(expectedDate, "2026-07-26")
        }
    }

    func testOfficialExportRangeRequiresMatchingAmountAndCostFiles() {
        XCTAssertThrowsError(
            try UsageAutoImportService.exportDateRange(from: [
                "amount-2026-07-01_2026-07-26.csv",
                "cost-2026-07-02_2026-07-26.csv",
            ])
        )
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

    private func write(_ data: Data, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
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
