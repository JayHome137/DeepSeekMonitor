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
            "account,20260725,deepseek-v4-pro,paid,1.2345,USD",
        ]

        var amountData = Data([0xEF, 0xBB, 0xBF])
        amountData.append(Data((amountLines.joined(separator: "\r\n") + "\r\n").utf8))
        var costData = Data([0xEF, 0xBB, 0xBF])
        costData.append(Data((costLines.joined(separator: "\r\n") + "\r\n").utf8))

        let amountURL = try write(amountData, named: "amount-2026-07-20_2026-07-27.csv", in: directory)
        let costURL = try write(costData, named: "cost-2026-07-20_2026-07-27.csv", in: directory)
        let result = try UsageCSVImporter.importResult(from: amountURL, costURL: costURL)
        let record = try XCTUnwrap(result.records.first)

        XCTAssertFalse(result.fileNameEndDateIsInclusive)
        XCTAssertEqual(record.date, "2026-07-25")
        XCTAssertEqual(record.modelName, DeepSeekModel.pro.rawValue)
        XCTAssertEqual(record.totalTokens, 1_700)
        XCTAssertEqual(record.inputCacheHitTokens, 1_000)
        XCTAssertEqual(record.inputCacheMissTokens, 500)
        XCTAssertEqual(record.completionTokens, 200)
        XCTAssertEqual(record.requestCount, 3)
        XCTAssertEqual(record.costAmount(for: "USD"), decimal("1.2345"))
    }

    func testCurrentISOExportsWithBOMAndCRLFImportEndToEnd() throws {
        let directory = try makeTemporaryDirectory()
        let amountLines = [
            "user_id,start_time_iso,end_time_iso,model,api_key_name,api_key,type,price,amount",
            "account,2026-08-13T00:00:00+08:00,2026-08-14T00:00:00+08:00,deepseek-v4-pro,\"Team, Primary\",sk-masked,input_cache_hit_tokens,0.000000025,1000",
            "account,2026-08-13T00:00:00+08:00,2026-08-14T00:00:00+08:00,deepseek-v4-pro,\"Team, Primary\",sk-masked,input_cache_miss_tokens,0.000003,500",
            "account,2026-08-13T00:00:00+08:00,2026-08-14T00:00:00+08:00,deepseek-v4-pro,\"Team, Primary\",sk-masked,output_tokens,0.000006,200",
            "account,2026-08-13T00:00:00+08:00,2026-08-14T00:00:00+08:00,deepseek-v4-pro,\"Team, Primary\",sk-masked,request_count,,3",
        ]
        let costLines = [
            "user_id,start_time_iso,end_time_iso,model,wallet_type,cost,currency",
            "account,2026-08-13T00:00:00+08:00,2026-08-14T00:00:00+08:00,deepseek-v4-pro,paid,1.2345,CNY",
        ]
        var amountData = Data([0xEF, 0xBB, 0xBF])
        amountData.append(Data((amountLines.joined(separator: "\r\n") + "\r\n").utf8))
        var costData = Data([0xEF, 0xBB, 0xBF])
        costData.append(Data((costLines.joined(separator: "\r\n") + "\r\n").utf8))

        let amountURL = try write(amountData, named: "amount-2026-08-01_2026-08-14.csv", in: directory)
        let costURL = try write(costData, named: "cost-2026-08-01_2026-08-14.csv", in: directory)
        let result = try UsageCSVImporter.importResult(from: amountURL, costURL: costURL)
        let record = try XCTUnwrap(result.records.first)

        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.timeZoneSecondsFromGMT, 8 * 60 * 60)
        XCTAssertTrue(result.fileNameEndDateIsInclusive)
        XCTAssertEqual(record.date, "2026-08-13")
        XCTAssertEqual(record.totalTokens, 1_700)
        XCTAssertEqual(record.inputCacheHitTokens, 1_000)
        XCTAssertEqual(record.inputCacheMissTokens, 500)
        XCTAssertEqual(record.completionTokens, 200)
        XCTAssertEqual(record.requestCount, 3)
        XCTAssertEqual(record.costAmount(for: "CNY"), decimal("1.2345"))
    }

    func testISOExportKeepsCalendarDateForUTCAndPositiveOffsets() throws {
        let directory = try makeTemporaryDirectory()
        let cases = [(suffix: "utc", zone: "+00:00", seconds: 0),
                     (suffix: "east", zone: "+08:00", seconds: 8 * 60 * 60)]

        for item in cases {
            let amountURL = try write(
                """
                user_id,start_time_iso,end_time_iso,model,api_key_name,api_key,type,price,amount
                account,2026-08-13T00:00:00\(item.zone),2026-08-14T00:00:00\(item.zone),deepseek-v4-flash,test,sk-masked,output_tokens,0,1
                """,
                named: "amount-\(item.suffix).csv",
                in: directory
            )
            let result = try UsageCSVImporter.importResult(from: amountURL)

            XCTAssertEqual(result.records.first?.date, "2026-08-13")
            XCTAssertEqual(result.timeZoneSecondsFromGMT, item.seconds)
            XCTAssertTrue(result.fileNameEndDateIsInclusive)
        }
    }

    func testAmountAndCostRejectDifferentOffsetsForTheSameDate() throws {
        let directory = try makeTemporaryDirectory()
        let amountURL = try write(
            """
            user_id,start_time_iso,end_time_iso,model,api_key_name,api_key,type,price,amount
            account,2026-08-13T00:00:00+08:00,2026-08-14T00:00:00+08:00,deepseek-v4-flash,test,sk-masked,output_tokens,0,1
            """,
            named: "amount.csv",
            in: directory
        )
        let costURL = try write(
            """
            user_id,start_time_iso,end_time_iso,model,wallet_type,cost,currency
            account,2026-08-13T00:00:00+00:00,2026-08-14T00:00:00+00:00,deepseek-v4-flash,paid,0.01,CNY
            """,
            named: "cost.csv",
            in: directory
        )

        XCTAssertThrowsError(
            try UsageCSVImporter.importRecords(from: amountURL, costURL: costURL)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("导出时区不一致"))
        }
    }

    func testInvalidISOIntervalsAreRejectedWithoutChangingCacheOrExposingRows() throws {
        let directory = try makeTemporaryDirectory()
        let suiteName = "DeepSeekMonitorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = LocalCache(defaults: defaults)
        cache.saveUsageRecords([makeUsageRecord(date: "2026-08-12", model: .flash, tokens: 99)])

        let invalidRows = [
            "private-user,not-an-iso-time,2026-08-14T00:00:00+08:00,deepseek-v4-flash,private-key-name,sensitive-key-value,output_tokens,0,1",
            "private-user,2026-08-14T00:00:00+08:00,2026-08-13T00:00:00+08:00,deepseek-v4-flash,private-key-name,sensitive-key-value,output_tokens,0,1",
        ]
        for (index, row) in invalidRows.enumerated() {
            let amountURL = try write(
                """
                user_id,start_time_iso,end_time_iso,model,api_key_name,api_key,type,price,amount
                \(row)
                """,
                named: "amount-invalid-\(index).csv",
                in: directory
            )

            XCTAssertThrowsError(try UsageCSVImporter.importRecords(from: amountURL)) { error in
                let message = error.localizedDescription
                XCTAssertFalse(message.contains("private-user"))
                XCTAssertFalse(message.contains("private-key-name"))
                XCTAssertFalse(message.contains("sensitive-key-value"))
            }
            XCTAssertEqual(cache.loadUsageRecords().map(\.totalTokens), [99])
        }

        let validAmountURL = try write(
            """
            user_id,start_time_iso,end_time_iso,model,api_key_name,api_key,type,price,amount
            account,2026-08-13T00:00:00+08:00,2026-08-14T00:00:00+08:00,deepseek-v4-flash,test,masked-key,output_tokens,0,1
            """,
            named: "amount-valid.csv",
            in: directory
        )
        let invalidCostURL = try write(
            """
            user_id,start_time_iso,end_time_iso,model,wallet_type,cost,currency
            private-user,not-an-iso-time,2026-08-14T00:00:00+08:00,deepseek-v4-flash,paid,0.01,CNY
            """,
            named: "cost-invalid.csv",
            in: directory
        )
        XCTAssertThrowsError(
            try UsageCSVImporter.importRecords(from: validAmountURL, costURL: invalidCostURL)
        ) { error in
            XCTAssertFalse(error.localizedDescription.contains("private-user"))
        }
        XCTAssertEqual(cache.loadUsageRecords().map(\.totalTokens), [99])
    }

    func testISOExportRequiresPairedTimeColumns() throws {
        let directory = try makeTemporaryDirectory()
        let amountURL = try write(
            """
            user_id,start_time_iso,model,api_key_name,api_key,type,price,amount
            account,2026-08-13T00:00:00+08:00,deepseek-v4-flash,test,sk-masked,output_tokens,0,1
            """,
            named: "amount-missing-end.csv",
            in: directory
        )

        XCTAssertThrowsError(try UsageCSVImporter.importRecords(from: amountURL)) { error in
            XCTAssertTrue(error.localizedDescription.contains("start_time_iso"))
            XCTAssertTrue(error.localizedDescription.contains("end_time_iso"))
        }
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

    func testUsageDateComparisonUsesExportTimeZone() throws {
        let formatter = ISO8601DateFormatter()
        let reference = try XCTUnwrap(formatter.date(from: "2026-06-30T16:30:00Z"))
        let exportTimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))

        XCTAssertTrue(UsageTime.isSameDay("2026-06-30", as: reference))
        XCTAssertFalse(UsageTime.isSameDay("2026-07-01", as: reference))
        XCTAssertTrue(UsageTime.isSameDay("2026-07-01", as: reference, timeZone: exportTimeZone))
        XCTAssertTrue(UsageTime.isSameMonth("2026-07-01", as: reference, timeZone: exportTimeZone))
        XCTAssertFalse(UsageTime.isSameMonth("2026-06-01", as: reference, timeZone: exportTimeZone))
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
            named: "amount-2026-07-20_2026-07-27.csv",
            in: exportDirectory
        )
        _ = try write(
            """
            api_key_name,utc_date,model,currency,wallet_type,cost
            test,2026-07-24,deepseek-v4-flash,USD,paid,0.25
            """,
            named: "cost-2026-07-20_2026-07-27.csv",
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

        XCTAssertEqual(
            Set(prepared.selectedNames),
            ["amount-2026-07-20_2026-07-27.csv", "cost-2026-07-20_2026-07-27.csv"]
        )
        XCTAssertEqual(record.totalTokens, 2)
        XCTAssertEqual(record.costAmount(for: "USD"), decimal("0.25"))
    }

    func testExternalOfficialZIPMatchesExpectedAggregatesWhenConfigured() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let zipPath = environment["DEEPSEEK_USAGE_ZIP"],
              let expectedCost = environment["DEEPSEEK_EXPECTED_COST"],
              let expectedTokens = environment["DEEPSEEK_EXPECTED_TOKENS"].flatMap(Int.init),
              let expectedRequests = environment["DEEPSEEK_EXPECTED_REQUESTS"].flatMap(Int.init) else {
            throw XCTSkip("External official ZIP validation is not configured")
        }

        let workspaceDirectory = try makeTemporaryDirectory()
        let prepared = try UsageAutoImportService.prepareManagedCSV(
            from: URL(fileURLWithPath: zipPath),
            workspaceFolder: workspaceDirectory
        )
        let records = try UsageCSVImporter.importRecords(
            from: prepared.amountURL,
            costURL: try XCTUnwrap(prepared.costURL),
            defaultCurrencyCode: "CNY"
        )

        XCTAssertEqual(
            records.reduce(Decimal.zero) { $0 + $1.costAmount(for: "CNY") },
            decimal(expectedCost)
        )
        XCTAssertEqual(records.reduce(0) { $0 + $1.totalTokens }, expectedTokens)
        XCTAssertEqual(records.reduce(0) { $0 + $1.requestCount }, expectedRequests)
    }

    func testCurrentOfficialCSVPairImportsWhenConfigured() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let amountPath = environment["DEEPSEEK_USAGE_AMOUNT_CSV"],
              let costPath = environment["DEEPSEEK_USAGE_COST_CSV"] else {
            throw XCTSkip("External current CSV pair validation is not configured")
        }

        let result = try UsageCSVImporter.importResult(
            from: URL(fileURLWithPath: amountPath),
            costURL: URL(fileURLWithPath: costPath)
        )

        XCTAssertFalse(result.records.isEmpty)
        XCTAssertNotNil(result.timeZoneSecondsFromGMT)
        XCTAssertTrue(result.fileNameEndDateIsInclusive)
        XCTAssertGreaterThan(result.records.reduce(0) { $0 + $1.totalTokens }, 0)
        XCTAssertGreaterThan(result.records.reduce(0) { $0 + $1.requestCount }, 0)
        XCTAssertTrue(result.records.allSatisfy {
            $0.date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        })
    }

    func testAutomaticExportAcceptsCurrentAndNextDayExclusiveBoundariesInExportTimeZone() throws {
        let formatter = ISO8601DateFormatter()
        let referenceDate = try XCTUnwrap(formatter.date(from: "2026-08-13T16:30:00Z"))
        let exportTimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))
        let placeholder = URL(fileURLWithPath: "/tmp/usage-export.zip")

        func candidate(_ range: UsageAutoImportService.ExportDateRange) -> UsageAutoImportService.ImportCandidate {
            UsageAutoImportService.ImportCandidate(
                sourceURL: placeholder,
                preparedAmountCSVURL: placeholder,
                preparedCostCSVURL: placeholder,
                fingerprint: "\(range.startDate)-\(range.endDateExclusive)",
                sourceName: placeholder.lastPathComponent,
                selectedCSVNames: [],
                exportDateRange: range,
                isArchive: true
            )
        }

        XCTAssertEqual(
            UsageAutoImportService.expectedCurrentMonthExportRange(
                referenceDate: referenceDate,
                timeZone: exportTimeZone
            ),
            .init(startDate: "2026-08-01", endDateExclusive: "2026-08-15")
        )
        for endDate in ["2026-08-14", "2026-08-15"] {
            let range = UsageAutoImportService.ExportDateRange(
                startDate: "2026-08-01",
                endDateExclusive: endDate
            )
            XCTAssertNoThrow(
                try UsageAutoImportService.validateAutomaticExport(
                    candidate(range),
                    exportDateRange: range,
                    referenceDate: referenceDate,
                    timeZone: exportTimeZone
                )
            )
        }

        let rejectedRanges: [UsageAutoImportService.ExportDateRange] = [
            .init(startDate: "2026-07-01", endDateExclusive: "2026-08-14"),
            .init(startDate: "2026-08-01", endDateExclusive: "2026-08-13"),
            .init(startDate: "2026-08-01", endDateExclusive: "2026-08-16"),
            .init(startDate: "2026-09-01", endDateExclusive: "2026-09-02"),
        ]
        for range in rejectedRanges {
            XCTAssertThrowsError(
                try UsageAutoImportService.validateAutomaticExport(
                    candidate(range),
                    exportDateRange: range,
                    referenceDate: referenceDate,
                    timeZone: exportTimeZone
                )
            ) { error in
                guard case UsageCSVImportError.staleExportRange = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }

        XCTAssertEqual(
            UsageAutoImportService.expectedRecentExportRange(
                referenceDate: referenceDate,
                timeZone: exportTimeZone
            ),
            .init(startDate: "2026-08-08", endDateExclusive: "2026-08-15")
        )
    }

    func testInclusiveFilenameEndIsNormalizedBeforeAutomaticValidation() throws {
        let formatter = ISO8601DateFormatter()
        let referenceDate = try XCTUnwrap(formatter.date(from: "2026-08-14T08:30:00Z"))
        let exportTimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))
        let declaredRange = UsageAutoImportService.ExportDateRange(
            startDate: "2026-08-01",
            endDateExclusive: "2026-08-14"
        )
        let records = [
            makeUsageRecord(date: "2026-08-01", model: .flash, tokens: 10),
            makeUsageRecord(date: "2026-08-14", model: .pro, tokens: 20),
        ]
        let resolvedRange = try XCTUnwrap(
            UsageAutoImportService.resolvedExportDateRange(
                declaredRange,
                records: records,
                fileNameEndDateIsInclusive: true
            )
        )
        let placeholder = URL(fileURLWithPath: "/tmp/usage-export.zip")
        let candidate = UsageAutoImportService.ImportCandidate(
            sourceURL: placeholder,
            preparedAmountCSVURL: placeholder,
            preparedCostCSVURL: placeholder,
            fingerprint: "inclusive-end",
            sourceName: placeholder.lastPathComponent,
            selectedCSVNames: [],
            exportDateRange: declaredRange,
            isArchive: true
        )

        XCTAssertEqual(
            resolvedRange,
            .init(startDate: "2026-08-01", endDateExclusive: "2026-08-15")
        )
        XCTAssertEqual(
            try UsageAutoImportService.resolvedExportDateRange(
                declaredRange,
                records: [makeUsageRecord(date: "2026-08-13", model: .flash, tokens: 10)],
                fileNameEndDateIsInclusive: true
            ),
            resolvedRange
        )
        XCTAssertNoThrow(
            try UsageAutoImportService.validateAutomaticExport(
                candidate,
                exportDateRange: resolvedRange,
                referenceDate: referenceDate,
                timeZone: exportTimeZone
            )
        )
    }

    func testExclusiveFilenameEndRemainsUnchanged() throws {
        let declaredRange = UsageAutoImportService.ExportDateRange(
            startDate: "2026-08-01",
            endDateExclusive: "2026-08-14"
        )
        let records = [
            makeUsageRecord(date: "2026-08-13", model: .flash, tokens: 10),
        ]

        XCTAssertEqual(
            try UsageAutoImportService.resolvedExportDateRange(
                declaredRange,
                records: records,
                fileNameEndDateIsInclusive: false
            ),
            declaredRange
        )
    }

    func testRangeNormalizationStillRejectsRecordsPastInclusiveEnd() {
        let declaredRange = UsageAutoImportService.ExportDateRange(
            startDate: "2026-08-01",
            endDateExclusive: "2026-08-14"
        )
        let records = [
            makeUsageRecord(date: "2026-08-14", model: .flash, tokens: 10),
            makeUsageRecord(date: "2026-08-15", model: .pro, tokens: 20),
        ]

        XCTAssertThrowsError(
            try UsageAutoImportService.resolvedExportDateRange(
                declaredRange,
                records: records,
                fileNameEndDateIsInclusive: true
            )
        )
    }

    func testOfficialExportRequiresMatchingAmountAndCostRanges() {
        XCTAssertThrowsError(
            try UsageAutoImportService.exportDateRange(from: [
                "amount-2026-07-20_2026-07-27.csv",
                "cost-2026-07-19_2026-07-27.csv",
            ])
        )
    }

    func testOfficialMonthAndThirtyDayRangesRemainValidForManualImport() throws {
        XCTAssertEqual(
            try UsageAutoImportService.exportDateRange(from: [
                "amount-2026-07-01_2026-07-27.csv",
                "cost-2026-07-01_2026-07-27.csv",
            ]),
            .init(startDate: "2026-07-01", endDateExclusive: "2026-07-27")
        )
        XCTAssertEqual(
            try UsageAutoImportService.exportDateRange(from: [
                "amount-2026-06-27_2026-07-27.csv",
                "cost-2026-06-27_2026-07-27.csv",
            ]),
            .init(startDate: "2026-06-27", endDateExclusive: "2026-07-27")
        )
    }

    func testJSONMasqueradingAsZIPIsRejectedBeforeImport() throws {
        let directory = try makeTemporaryDirectory()
        let jsonURL = try write(
            Data(#"{"code":0,"data":{"biz_msg":"INVALID_PARAM"}}"#.utf8),
            named: "usage-export.zip",
            in: directory
        )

        XCTAssertFalse(UsageExportAutomationService.isZIPArchiveData(try Data(contentsOf: jsonURL)))
        XCTAssertThrowsError(try UsageAutoImportService.prepareImportCandidate(from: jsonURL))
    }

    func testUsageExportAllowsOnlyOfficialHTTPSPlatformURLAndOrigin() throws {
        XCTAssertTrue(UsageExportAutomationService.isAllowedPlatformURL(
            URL(string: "https://platform.deepseek.com/usage")
        ))
        XCTAssertTrue(UsageExportAutomationService.isAllowedPlatformURL(
            URL(string: "https://platform.deepseek.com:443/sign_in?redirect=/usage")
        ))

        let rejectedURLs = [
            "http://platform.deepseek.com/usage",
            "https://platform.deepseek.com.evil.example/usage",
            "https://platform.deepseek.com@evil.example/usage",
            "https://platform.deepseek.com:8443/usage",
            "https://api.deepseek.com/usage",
        ]
        for rawURL in rejectedURLs {
            XCTAssertFalse(
                UsageExportAutomationService.isAllowedPlatformURL(try XCTUnwrap(URL(string: rawURL))),
                rawURL
            )
        }

        XCTAssertTrue(UsageExportAutomationService.isAllowedPlatformOrigin(
            scheme: "https",
            host: "platform.deepseek.com",
            port: 0
        ))
        XCTAssertTrue(UsageExportAutomationService.isAllowedPlatformOrigin(
            scheme: "HTTPS",
            host: "PLATFORM.DEEPSEEK.COM",
            port: 443
        ))
        XCTAssertFalse(UsageExportAutomationService.isAllowedPlatformOrigin(
            scheme: "http",
            host: "platform.deepseek.com",
            port: 0
        ))
        XCTAssertFalse(UsageExportAutomationService.isAllowedPlatformOrigin(
            scheme: "https",
            host: "platform.deepseek.com.evil.example",
            port: 443
        ))
        XCTAssertFalse(UsageExportAutomationService.isAllowedPlatformOrigin(
            scheme: "https",
            host: "platform.deepseek.com",
            port: 8443
        ))
    }

    func testZIPPathTraversalAndBackslashPathsAreRejected() throws {
        let directory = try makeTemporaryDirectory()
        for (index, entryName) in ["../amount.csv", "/absolute/amount.csv", "folder\\amount.csv"].enumerated() {
            let archiveURL = try write(
                makeStoredZIP(entryName: entryName, contents: Data("x".utf8)),
                named: "invalid-path-\(index).zip",
                in: directory
            )
            XCTAssertThrowsError(try UsageAutoImportService.validateZIPArchive(at: archiveURL), entryName)
        }
    }

    func testZIPUnixSymbolicLinkIsRejected() throws {
        let directory = try makeTemporaryDirectory()
        let archiveURL = try write(
            makeStoredZIP(
                entryName: "amount-2026-08-01_2026-08-15.csv",
                contents: Data("../../outside.csv".utf8),
                versionMadeBy: 0x0314,
                externalAttributes: UInt32(0o120777) << 16
            ),
            named: "symlink.zip",
            in: directory
        )

        XCTAssertThrowsError(try UsageAutoImportService.validateZIPArchive(at: archiveURL))
    }

    func testZIPDeclaredOversizedFileIsRejectedBeforeExtraction() throws {
        let directory = try makeTemporaryDirectory()
        let archiveURL = try write(
            makeStoredZIP(
                entryName: "amount-2026-08-01_2026-08-15.csv",
                contents: Data(),
                declaredUncompressedSize: UInt32(128 * 1024 * 1024 + 1)
            ),
            named: "oversized.zip",
            in: directory
        )

        XCTAssertThrowsError(try UsageAutoImportService.validateZIPArchive(at: archiveURL))
    }

    func testRecordsOutsideDeclaredExportRangeAreRejected() {
        let range = UsageAutoImportService.ExportDateRange(
            startDate: "2026-07-20",
            endDateExclusive: "2026-07-27"
        )
        let records = [makeUsageRecord(date: "2026-07-19", model: .flash, tokens: 10)]

        XCTAssertThrowsError(try UsageAutoImportService.validateRecords(records, within: range))
    }

    func testUsageCacheReplacesExportRangeAndKeepsCurrentMonthHistory() throws {
        let formatter = ISO8601DateFormatter()
        let referenceDate = try XCTUnwrap(formatter.date(from: "2026-07-26T12:00:00Z"))
        let range = UsageAutoImportService.ExportDateRange(
            startDate: "2026-07-20",
            endDateExclusive: "2026-07-27"
        )
        let existing = [
            makeUsageRecord(date: "2026-06-30", model: .flash, tokens: 1),
            makeUsageRecord(date: "2026-07-01", model: .flash, tokens: 2),
            makeUsageRecord(date: "2026-07-20", model: .flash, tokens: 3),
            makeUsageRecord(date: "2026-07-21", model: .pro, tokens: 4),
        ]
        let incoming = [
            makeUsageRecord(date: "2026-07-20", model: .flash, tokens: 30),
            makeUsageRecord(date: "2026-07-25", model: .pro, tokens: 50),
        ]

        let merged = LocalCache.mergedUsageRecords(
            existing: existing,
            incoming: incoming,
            replacing: range,
            referenceDate: referenceDate
        )

        XCTAssertEqual(merged.map(\.date), ["2026-07-01", "2026-07-20", "2026-07-25"])
        XCTAssertEqual(merged.map(\.totalTokens), [2, 30, 50])
    }

    func testSchema3BaselineUsesExportTimeZoneAndDiscardsLegacyUTCHistory() throws {
        let formatter = ISO8601DateFormatter()
        let referenceDate = try XCTUnwrap(formatter.date(from: "2026-08-02T16:30:00Z"))
        let exportTimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))
        let suiteName = "DeepSeekMonitorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cache = LocalCache(defaults: defaults)
        defaults.set(2, forKey: "cached_usage_history_schema_version")
        defaults.set("2026-08", forKey: "cached_usage_baseline_month")
        cache.saveUsageRecords([
            makeUsageRecord(date: "2026-07-31", model: .flash, tokens: 10),
            makeUsageRecord(date: "2026-08-01", model: .flash, tokens: 20),
        ])
        XCTAssertTrue(
            cache.needsCurrentMonthBaseline(
                referenceDate: referenceDate,
                timeZone: exportTimeZone
            )
        )

        let range = UsageAutoImportService.ExportDateRange(
            startDate: "2026-08-01",
            endDateExclusive: "2026-08-03"
        )
        let incoming = [
            makeUsageRecord(date: "2026-08-01", model: .flash, tokens: 200),
            makeUsageRecord(date: "2026-08-02", model: .pro, tokens: 300),
        ]
        let merged = cache.mergeUsageRecords(
            incoming,
            replacing: range,
            referenceDate: referenceDate,
            timeZone: exportTimeZone
        )
        cache.saveUsageTimeZone(secondsFromGMT: 8 * 60 * 60)

        XCTAssertEqual(merged.map(\.date), ["2026-08-01", "2026-08-02"])
        XCTAssertEqual(merged.map(\.totalTokens), [200, 300])
        XCTAssertEqual(defaults.integer(forKey: "cached_usage_history_schema_version"), 3)
        XCTAssertEqual(cache.usageTimeZone.secondsFromGMT(), 8 * 60 * 60)
        XCTAssertFalse(
            cache.needsCurrentMonthBaseline(
                referenceDate: referenceDate,
                timeZone: exportTimeZone
            )
        )

        let nextMonth = try XCTUnwrap(formatter.date(from: "2026-08-31T16:30:00Z"))
        XCTAssertTrue(
            cache.needsCurrentMonthBaseline(
                referenceDate: nextMonth,
                timeZone: exportTimeZone
            )
        )
    }

    func testCurrencyDisplayTruncatesToMatchDeepSeekWeb() {
        XCTAssertEqual(formattedCurrency(decimal("12.3499"), currencyCode: "CNY"), "¥12.34")
        XCTAssertEqual(formattedCurrency(decimal("8.501"), currencyCode: "CNY"), "¥8.50")
        XCTAssertEqual(formattedCurrency(51.44, currencyCode: "CNY"), "¥51.44")
        XCTAssertEqual(formattedCurrency(12.3499, currencyCode: "CNY"), "¥12.34")
        XCTAssertEqual(formattedCurrency(decimal("0.008"), currencyCode: "USD"), "$0.00")

        let summary = ModelUsageSummary(
            model: .flash,
            totalTokens: 1,
            costAmount: decimal("0.008"),
            currencyCode: "USD"
        )
        XCTAssertEqual(summary.costInCents, 0)
    }

    func testBalanceSelectionUsesOnlyNonZeroUSDAndMatchesUsageCurrency() throws {
        let response = BalanceResponse(
            isAvailable: true,
            balanceInfos: [
                BalanceInfo(currency: "CNY", totalBalance: "0", grantedBalance: "0", toppedUpBalance: "0"),
                BalanceInfo(currency: "USD", totalBalance: "12.50", grantedBalance: "2.50", toppedUpBalance: "10"),
            ]
        )

        XCTAssertEqual(response.preferredBalanceInfo(matching: "CNY")?.currency, "USD")

        let multiCurrency = BalanceResponse(
            isAvailable: true,
            balanceInfos: [
                BalanceInfo(currency: "CNY", totalBalance: "8", grantedBalance: "0", toppedUpBalance: "8"),
                BalanceInfo(currency: "USD", totalBalance: "12.50", grantedBalance: "2.50", toppedUpBalance: "10"),
            ]
        )
        XCTAssertEqual(multiCurrency.preferredBalanceInfo(matching: "USD")?.currency, "USD")
        XCTAssertEqual(currencySymbol(for: "USD"), "$")
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

    private func makeUsageRecord(
        date: String,
        model: DeepSeekModel,
        tokens: Int
    ) -> UsageRecord {
        UsageRecord(
            id: "\(date)-\(model.rawValue)",
            modelName: model.rawValue,
            totalTokens: tokens,
            promptTokens: tokens,
            completionTokens: 0,
            costByCurrency: ["USD": Decimal(tokens) / Decimal(100)],
            date: date,
            requestCount: 1
        )
    }

    private func createZIP(from directory: URL, at destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", directory.path, destination.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func makeStoredZIP(
        entryName: String,
        contents: Data,
        declaredUncompressedSize: UInt32? = nil,
        versionMadeBy: UInt16 = 0x0014,
        externalAttributes: UInt32 = 0
    ) -> Data {
        let name = Data(entryName.utf8)
        let compressedSize = UInt32(contents.count)
        let uncompressedSize = declaredUncompressedSize ?? compressedSize

        var archive = Data()
        archive.appendZIPUInt32(0x04034B50)
        archive.appendZIPUInt16(20)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt32(0)
        archive.appendZIPUInt32(compressedSize)
        archive.appendZIPUInt32(uncompressedSize)
        archive.appendZIPUInt16(UInt16(name.count))
        archive.appendZIPUInt16(0)
        archive.append(name)
        archive.append(contents)

        let centralDirectoryOffset = UInt32(archive.count)
        archive.appendZIPUInt32(0x02014B50)
        archive.appendZIPUInt16(versionMadeBy)
        archive.appendZIPUInt16(20)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt32(0)
        archive.appendZIPUInt32(compressedSize)
        archive.appendZIPUInt32(uncompressedSize)
        archive.appendZIPUInt16(UInt16(name.count))
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt32(externalAttributes)
        archive.appendZIPUInt32(0)
        archive.append(name)

        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset
        archive.appendZIPUInt32(0x06054B50)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt16(0)
        archive.appendZIPUInt16(1)
        archive.appendZIPUInt16(1)
        archive.appendZIPUInt32(centralDirectorySize)
        archive.appendZIPUInt32(centralDirectoryOffset)
        archive.appendZIPUInt16(0)
        return archive
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}

private extension Data {
    mutating func appendZIPUInt16(_ value: UInt16) {
        append(contentsOf: [
            UInt8(value & 0x00FF),
            UInt8((value >> 8) & 0x00FF),
        ])
    }

    mutating func appendZIPUInt32(_ value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0x000000FF),
            UInt8((value >> 8) & 0x000000FF),
            UInt8((value >> 16) & 0x000000FF),
            UInt8((value >> 24) & 0x000000FF),
        ])
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
