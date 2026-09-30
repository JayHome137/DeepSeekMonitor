import Foundation
import XCTest
@testable import DeepSeekMonitor

final class ModelCompatibilityTests: XCTestCase {
    func testCurrentAndHistoricalNamesUseTheTwoDisplayedBuckets() {
        XCTAssertEqual(DeepSeekModel.from(rawName: "deepseek-flash"), .flash)
        XCTAssertEqual(DeepSeekModel.from(rawName: " DEEPSEEK-FLASH "), .flash)
        XCTAssertEqual(DeepSeekModel.from(rawName: "deepseek-v4-flash"), .flash)
        XCTAssertEqual(DeepSeekModel.from(rawName: "deepseek-v4-flash-vision-exp"), .flash)
        XCTAssertEqual(DeepSeekModel.from(rawName: "deepseek-chat"), .flash)
        XCTAssertEqual(DeepSeekModel.from(rawName: "deepseek-v4-pro"), .pro)
        XCTAssertEqual(DeepSeekModel.from(rawName: "deepseek-v4-pro-0813"), .pro)
        XCTAssertEqual(DeepSeekModel.from(rawName: "deepseek-reasoner"), .pro)
        XCTAssertNil(DeepSeekModel.from(rawName: "deepseek-v5-flash"))
    }

    func testDisplayNamesMatchCurrentUsagePage() {
        XCTAssertEqual(DeepSeekModel.flash.displayName, "V4.1 Flash")
        XCTAssertEqual(DeepSeekModel.pro.displayName, "V4 Pro")
        XCTAssertEqual(DeepSeekModel.allCases, [.flash, .pro])
    }

    func testLegacyV16DashboardCacheDoesNotRelabelRetiredFlashAsPro() throws {
        let payload: [String: Any] = [
            "isAccountAvailable": true,
            "totalBalance": 10.0,
            "grantedBalance": 1.0,
            "toppedUpBalance": 9.0,
            "balanceCurrencyCode": "CNY",
            "usageCurrencyCode": "CNY",
            "currentDayCost": 0.1,
            "currentMonthCost": 0.2,
            "flashTotalTokens": 100,
            "flashCostInCents": 12,
            "v4FlashTotalTokens": 900,
            "v4FlashCostInCents": 99,
            "dailyUsage": ["2026-09-15": 100],
            "balanceLastUpdated": "2026-09-15T00:00:00Z",
            "usageLastUpdated": "2026-09-15T00:00:00Z",
            "lastUpdated": "2026-09-15T00:00:00Z"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cache = try decoder.decode(DashboardCache.self, from: data)

        XCTAssertEqual(cache.flashTotalTokens, 100)
        XCTAssertEqual(cache.flashCostInCents, 12)
        XCTAssertEqual(cache.proTotalTokens, 0)
        XCTAssertEqual(cache.proCostInCents, 0)
    }

    func testPreV16DashboardCacheKeepsReasonerDataInProSlot() throws {
        let payload: [String: Any] = [
            "isAccountAvailable": true,
            "totalBalance": 10.0,
            "grantedBalance": 1.0,
            "toppedUpBalance": 9.0,
            "balanceCurrencyCode": "CNY",
            "usageCurrencyCode": "CNY",
            "currentDayCost": 0.1,
            "currentMonthCost": 0.2,
            "flashTotalTokens": 100,
            "flashCostInCents": 12,
            "proTotalTokens": 900,
            "proCostInCents": 99,
            "dailyUsage": ["2026-09-15": 100],
            "balanceLastUpdated": "2026-09-15T00:00:00Z",
            "usageLastUpdated": "2026-09-15T00:00:00Z",
            "lastUpdated": "2026-09-15T00:00:00Z"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cache = try decoder.decode(DashboardCache.self, from: data)

        XCTAssertEqual(cache.flashTotalTokens, 0)
        XCTAssertEqual(cache.flashCostInCents, 0)
        XCTAssertEqual(cache.proTotalTokens, 900)
        XCTAssertEqual(cache.proCostInCents, 99)
    }

    func testDashboardCacheEncodingWritesCurrentModelSchema() throws {
        let now = Date(timeIntervalSinceReferenceDate: 123_456)
        let cache = DashboardCache(
            isAccountAvailable: true,
            totalBalance: 10,
            grantedBalance: 1,
            toppedUpBalance: 9,
            balanceCurrencyCode: "CNY",
            usageCurrencyCode: "CNY",
            currentDayCost: 0.1,
            currentMonthCost: 0.2,
            flashTotalTokens: 100,
            flashCostInCents: 12,
            proTotalTokens: 900,
            proCostInCents: 99,
            dailyUsage: ["2026-09-15": 100],
            balanceLastUpdated: now,
            usageLastUpdated: now,
            lastUpdated: now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoder.encode(cache)) as? [String: Any]
        )

        XCTAssertEqual(object["modelSchemaVersion"] as? Int, 2)
        XCTAssertEqual(object["flashTotalTokens"] as? Int, 100)
        XCTAssertEqual(object["proTotalTokens"] as? Int, 900)
    }

    func testLegacyWidgetSnapshotDoesNotRelabelV16FlashAsPro() throws {
        let payload: [String: Any] = [
            "isWidgetEnabled": true,
            "totalBalance": 10.0,
            "isAccountAvailable": true,
            "balanceCurrencyCode": "CNY",
            "usageCurrencyCode": "CNY",
            "currentDayCost": 0.1,
            "currentMonthCost": 0.2,
            "flashCostInCents": 12,
            "v4FlashCostInCents": 99,
            "usageUpdatedAt": "2026-09-15T00:00:00Z",
            "lastUpdated": "2026-09-15T00:00:00Z"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(snapshot.flashCostInCents, 12)
        XCTAssertEqual(snapshot.proCostInCents, 0)
    }

    func testLegacyWidgetSnapshotKeepsPreV16ReasonerCostAsPro() throws {
        let payload: [String: Any] = [
            "isWidgetEnabled": true,
            "totalBalance": 10.0,
            "isAccountAvailable": true,
            "balanceCurrencyCode": "CNY",
            "usageCurrencyCode": "CNY",
            "currentDayCost": 0.1,
            "currentMonthCost": 0.2,
            "flashCostInCents": 12,
            "proCostInCents": 99,
            "usageUpdatedAt": "2026-09-15T00:00:00Z",
            "lastUpdated": "2026-09-15T00:00:00Z"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(snapshot.flashCostInCents, 0)
        XCTAssertEqual(snapshot.proCostInCents, 99)
    }
}
