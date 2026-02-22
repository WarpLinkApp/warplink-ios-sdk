import XCTest
@testable import WarpLink

final class StorageTests: XCTestCase {

    private var storage: Storage!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "StorageTests")!
        defaults.removePersistentDomain(forName: "StorageTests")
        storage = Storage(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "StorageTests")
        super.tearDown()
    }

    func testApiKeyValidatedAtDefaultNil() {
        XCTAssertNil(storage.apiKeyValidatedAt)
    }

    func testApiKeyValidatedAtRoundTrips() {
        let now = Date()
        storage.apiKeyValidatedAt = now
        let stored = storage.apiKeyValidatedAt
        XCTAssertNotNil(stored)
        XCTAssertEqual(
            stored!.timeIntervalSince1970,
            now.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testValidationCacheValidWithin24Hours() {
        storage.apiKeyValidatedAt = Date()
        XCTAssertTrue(storage.isApiKeyValidationCacheValid)
    }

    func testValidationCacheExpiredAfter24Hours() {
        let expired = Date().addingTimeInterval(-86401)
        storage.apiKeyValidatedAt = expired
        XCTAssertFalse(storage.isApiKeyValidationCacheValid)
    }

    func testClearAllRemovesValidation() {
        storage.apiKeyValidatedAt = Date()
        XCTAssertNotNil(storage.apiKeyValidatedAt)
        storage.clearAll()
        XCTAssertNil(storage.apiKeyValidatedAt)
    }
}
