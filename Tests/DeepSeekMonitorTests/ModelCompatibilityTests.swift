import Foundation
import XCTest
@testable import DeepSeekMonitor

final class ModelCompatibilityTests: XCTestCase {
    func testCurrentAndHistoricalFlashNamesUseTheTwoDisplayedBuckets() {
        XCTAssertEqual(DeepSeekModel.from(rawName: "deepseek-flash"), .flash)
        XCTAssertEqual(DeepSeekModel.from(rawName: " DEEPSEEK-FLASH "), .flash)
        XCTAssertEqual(DeepSeekModel.from(rawName: "deepseek-v4-flash"), .v4Flash)
        XCTAssertEqual(DeepSeekModel.from(rawName: "deepseek-v4-flash-vision-exp"), .v4Flash)
        XCTAssertEqual(DeepSeekModel.from(rawName: "deepseek-chat"), .v4Flash)
        XCTAssertNil(DeepSeekModel.from(rawName: "deepseek-reasoner"))
        XCTAssertNil(DeepSeekModel.from(rawName: "deepseek-v5-flash"))
    }

    func testDisplayNamesMatchCurrentUsagePage() {
        XCTAssertEqual(DeepSeekModel.flash.displayName, "V4.1 Flash")
        XCTAssertEqual(DeepSeekModel.v4Flash.displayName, "V4 Flash")
        XCTAssertEqual(DeepSeekModel.allCases, [.flash, .v4Flash])
    }

    func testLegacyDashboardCacheMovesOldFlashBucketToV4Flash() throws {
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
        XCTAssertEqual(cache.v4FlashTotalTokens, 100)
        XCTAssertEqual(cache.v4FlashCostInCents, 12)
    }
}
