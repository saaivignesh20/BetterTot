import Foundation
import XCTest
@testable import BetterTot

final class AutomaticUpdateCheckPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testBundledAutomaticCheckIsAllowedWhenNeverChecked() {
        XCTAssertTrue(AutomaticUpdateCheckPolicy.shouldCheck(
            for: .automatic,
            isBundledApp: true,
            now: now,
            lastSuccessfulAutomaticCheck: nil
        ))
    }

    func testBundledAutomaticCheckIsThrottledUntilTwentyFourHoursElapsed() {
        let justUnderTwentyFourHours = now.addingTimeInterval(-(24 * 60 * 60) + 1)
        let exactlyTwentyFourHours = now.addingTimeInterval(-(24 * 60 * 60))

        XCTAssertFalse(AutomaticUpdateCheckPolicy.shouldCheck(
            for: .automatic,
            isBundledApp: true,
            now: now,
            lastSuccessfulAutomaticCheck: justUnderTwentyFourHours
        ))
        XCTAssertTrue(AutomaticUpdateCheckPolicy.shouldCheck(
            for: .automatic,
            isBundledApp: true,
            now: now,
            lastSuccessfulAutomaticCheck: exactlyTwentyFourHours
        ))
    }

    func testUnbundledAutomaticCheckIsNeverAllowed() {
        XCTAssertFalse(AutomaticUpdateCheckPolicy.shouldCheck(
            for: .automatic,
            isBundledApp: false,
            now: now,
            lastSuccessfulAutomaticCheck: nil
        ))
        XCTAssertFalse(AutomaticUpdateCheckPolicy.shouldCheck(
            for: .automatic,
            isBundledApp: false,
            now: now,
            lastSuccessfulAutomaticCheck: now.addingTimeInterval(-(48 * 60 * 60))
        ))
    }

    func testManualCheckIsAlwaysAllowed() {
        XCTAssertTrue(AutomaticUpdateCheckPolicy.shouldCheck(
            for: .manual,
            isBundledApp: true,
            now: now,
            lastSuccessfulAutomaticCheck: now
        ))
        XCTAssertTrue(AutomaticUpdateCheckPolicy.shouldCheck(
            for: .manual,
            isBundledApp: false,
            now: now,
            lastSuccessfulAutomaticCheck: now.addingTimeInterval(60)
        ))
    }
}

final class AutomaticUpdateCheckStateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "BetterTot.AutomaticUpdateCheckStateTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testOnlySuccessfulAutomaticChecksArePersisted() {
        let state = AutomaticUpdateCheckState(defaults: defaults)
        let manualCheckDate = Date(timeIntervalSince1970: 1_900_000_000)
        let automaticCheckDate = Date(timeIntervalSince1970: 2_000_000_000)

        state.recordSuccessfulCheck(.manual, at: manualCheckDate)
        XCTAssertNil(state.lastSuccessfulCheckDate)

        state.recordSuccessfulCheck(.automatic, at: automaticCheckDate)

        let reloadedState = AutomaticUpdateCheckState(defaults: defaults)
        XCTAssertEqual(reloadedState.lastSuccessfulCheckDate, automaticCheckDate)
        let domain = defaults.persistentDomain(forName: suiteName)
        XCTAssertEqual(domain?.count, 1)
        XCTAssertEqual(
            domain?[AutomaticUpdateCheckState.lastSuccessfulCheckKey] as? Date,
            automaticCheckDate
        )
    }

    func testMalformedPersistedValueIsTreatedAsNeverChecked() {
        defaults.set(
            "not-a-date",
            forKey: AutomaticUpdateCheckState.lastSuccessfulCheckKey
        )

        let state = AutomaticUpdateCheckState(defaults: defaults)

        XCTAssertNil(state.lastSuccessfulCheckDate)
    }
}
