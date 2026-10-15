import XCTest
@testable import SpaceSweepCore

final class CleanupPlannerTests: XCTestCase {
    typealias ID = CleanupRuleRegistry.ID
    var fixture: Fixture!

    override func setUpWithError() throws {
        fixture = try Fixture()
        try fixture.file("Library", "Developer", "Xcode", "DerivedData", "App-a", "x", bytes: 5000)
        try fixture.file(".npm", "_cacache", "content-v2", "x", bytes: 5000)
        try fixture.file("Library", "Caches", "Yarn", "v6", "x", bytes: 5000)
        try fixture.file(".Trash", "old.zip", bytes: 5000)
        try fixture.file("Library", "Developer", "CoreSimulator", "Devices", "D", "x", bytes: 5000)
    }

    override func tearDown() { fixture = nil }

    func testDefaultSelectionPlansSafeOnly() async throws {
        let report = try await fixture.scan()
        let plan = try CleanupPlanner().makePlan(from: report, selectedIDs: report.defaultSelection)
        XCTAssertEqual(Set(plan.targets.map(\.ruleID)), [ID.xcodeDerivedData, ID.npmCache])
        XCTAssertEqual(plan.authorization, .pendingConfirmation)
        XCTAssertFalse(plan.containsReviewItems)
        XCTAssertEqual(plan.excludedReviewCount, 2) // Yarn + Trash
    }

    func testExplicitReviewSelectionIsPlanned() async throws {
        let report = try await fixture.scan()
        let yarn = try XCTUnwrap(report.result(for: ID.yarnCache)?.candidates.first)
        let plan = try CleanupPlanner().makePlan(from: report, selectedIDs: [yarn.id])
        XCTAssertEqual(plan.targets.map(\.ruleID), [ID.yarnCache])
        XCTAssertTrue(plan.containsReviewItems)
    }

    // 8 / 18
    func testOneClickPlanNeverIncludesReviewOrTrash() async throws {
        let report = try await fixture.scan()
        let plan = try CleanupPlanner().makeOneClickPlan(from: report)
        XCTAssertTrue(plan.targets.allSatisfy { $0.tier == .safe })
        XCTAssertFalse(plan.targets.contains { $0.ruleID == ID.trash || $0.ruleID == ID.yarnCache })
        XCTAssertNotNil(plan.authorizedByOneClickPreference())

        let reviewed = try CleanupPlanner().makePlan(from: report, selectedIDs: Set(report.allCandidates.map(\.id)))
        XCTAssertNil(reviewed.authorizedByOneClickPreference(), "reviewed plans can't use the one-click preference")
        XCTAssertTrue(reviewed.includesPermanentUserFileRemoval)
    }

    // 7 / 9
    func testProtectedAndBlockedCandidatesNeverEnterAPlan() async throws {
        let report = try await fixture.scan(running: [KnownApp.xcode.bundleIdentifier])
        let everything = Set(report.allCandidates.map(\.id))
        let plan = try CleanupPlanner().makePlan(from: report, selectedIDs: everything)
        XCTAssertFalse(plan.targets.contains { $0.tier == .protected || $0.tier == .blocked })
        XCTAssertFalse(plan.targets.contains { $0.ruleID == ID.simulatorDevices })
        XCTAssertFalse(plan.targets.contains { $0.ruleID == ID.xcodeDerivedData })
    }

    func testUnknownIDsProduceNoPlan() async throws {
        let report = try await fixture.scan()
        XCTAssertThrowsError(try CleanupPlanner().makePlan(from: report, selectedIDs: [UUID()])) { error in
            XCTAssertEqual(error as? PlanError, .nothingSelected)
        }
    }

    func testStaleScansExpire() async throws {
        let report = try await fixture.scan()
        let later = report.finishedAt.addingTimeInterval(CleanupPlanner.maximumScanAge + 1)
        let planner = CleanupPlanner(now: { later })
        XCTAssertThrowsError(try planner.makePlan(from: report, selectedIDs: report.defaultSelection)) { error in
            XCTAssertEqual(error as? PlanError, .scanExpired)
        }
    }

    func testRuleTierMismatchIsRejected() async throws {
        let report = try await fixture.scan()
        // A registry where DerivedData has been demoted to review must not accept the old safe candidates.
        let demoted = CleanupRuleRegistry.builtInRules.map { rule -> CleanupRule in
            guard rule.id == ID.xcodeDerivedData else { return rule }
            return CleanupRule(id: rule.id, title: rule.title, summary: rule.summary, explanation: rule.explanation,
                               consequence: rule.consequence, tier: .review, category: rule.category,
                               symbolName: rule.symbolName, rootComponents: rule.rootComponents)
        }
        let plan = try CleanupPlanner(registry: CleanupRuleRegistry(rules: demoted))
            .makePlan(from: report, selectedIDs: report.defaultSelection)
        XCTAssertEqual(plan.targets.map(\.ruleID), [ID.npmCache])
    }
}
