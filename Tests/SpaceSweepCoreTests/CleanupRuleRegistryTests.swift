import XCTest
@testable import SpaceSweepCore

final class CleanupRuleRegistryTests: XCTestCase {
    let registry = CleanupRuleRegistry.standard

    func testRuleIDsAreUnique() {
        let ids = registry.rules.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testOnlyNarrowRulesAreSafe() {
        let safe = registry.rules.filter { $0.tier == .safe }
        XCTAssertEqual(Set(safe.map(\.id)), [CleanupRuleRegistry.ID.xcodeDerivedData, CleanupRuleRegistry.ID.npmCache])
        for rule in safe {
            XCTAssertFalse(CleanupRuleRegistry.broadRoots.contains(rule.rootComponents), "\(rule.id) has a broad root")
            XCTAssertFalse(rule.removesUserFilesPermanently)
            XCTAssertEqual(rule.scope, .children)
        }
    }

    func testOnlySafeRulesAreSelectedByDefault() {
        for rule in registry.rules where rule.tier != .safe {
            XCTAssertFalse(rule.defaultSelected, rule.id)
        }
        // The initialiser enforces it too.
        let sneaky = CleanupRule(id: "x", title: "x", summary: "", explanation: "", consequence: "", tier: .review,
                                 category: .appCache, symbolName: "x", rootComponents: ["Library", "Caches", "x"],
                                 defaultSelected: true)
        XCTAssertFalse(sneaky.defaultSelected)
    }

    func testBroadRootsAreOnlyUsedByReviewRules() {
        for rule in registry.rules where CleanupRuleRegistry.broadRoots.contains(rule.rootComponents) {
            XCTAssertEqual(rule.tier, .review, rule.id)
            XCTAssertFalse(rule.defaultSelected, rule.id)
        }
    }

    func testProtectedRulesAreDisplayOnly() {
        for rule in registry.rules where rule.tier == .protected {
            XCTAssertEqual(rule.scope, .displayOnlyAggregate, rule.id)
            XCTAssertFalse(rule.isDeletable, rule.id)
            XCTAssertNotNil(rule.managementHint, rule.id)
        }
    }

    func testTrashIsReviewAndPermanent() {
        let trash = registry.rule(id: CleanupRuleRegistry.ID.trash)!
        XCTAssertEqual(trash.tier, .review)
        XCTAssertTrue(trash.removesUserFilesPermanently)
        XCTAssertFalse(trash.defaultSelected)
    }

    func testRootsAreWellFormed() {
        for rule in registry.rules {
            XCTAssertFalse(rule.rootComponents.isEmpty, rule.id)
            XCTAssertFalse(rule.rootComponents.contains { $0 == ".." || $0 == "." || $0.contains("/") }, rule.id)
        }
    }

    /// Every deletable rule's root is not protected, and protected display-only roots are.
    func testDeletableRootsAreNotProtected() {
        let validator = PathSafetyValidator(environment: PathEnvironment(homeDirectory: URL(fileURLWithPath: "/Users/tester")))
        for rule in registry.rules {
            let root = rule.rootURL(in: validator.environment)
            if rule.isDeletable {
                XCTAssertFalse(validator.isProtected(root), rule.id)
            } else {
                XCTAssertTrue(validator.isProtected(root), rule.id)
            }
        }
    }

    // 20: every shipped deletable rule has allowed and denied examples.
    func testEveryDeletableRuleAllowsChildrenAndDeniesEscapes() throws {
        for rule in registry.rules where rule.isDeletable {
            let fixture = try Fixture()
            let validator = PathSafetyValidator(environment: fixture.environment)
            let root = rule.rootURL(in: fixture.environment)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            // Allowed: a regular child.
            let child = root.appendingPathComponent("allowed-child")
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            XCTAssertNotNil(try? validator.validate(target: child, root: root).get(), "\(rule.id) should allow a child")

            // Denied: the root itself.
            XCTAssertEqual(validator.validate(target: root, root: root).failure, .isRootItself, rule.id)
            // Denied: a similar-prefix sibling.
            let sibling = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-evil")
                .appendingPathComponent("x")
            try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
            XCTAssertEqual(validator.validate(target: sibling, root: root).failure, .notInsideRoot, rule.id)
            // Denied: traversal.
            let traversal = root.appendingPathComponent("..").appendingPathComponent(root.lastPathComponent + "-evil")
            XCTAssertEqual(validator.validate(target: traversal, root: root).failure, .containsTraversal, rule.id)
            // Denied: a symlink child pointing outside.
            let link = root.appendingPathComponent("escape")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.outside)
            XCTAssertEqual(validator.validate(target: link, root: root).failure, .symbolicLink, rule.id)
            // Denied: something in Documents.
            let doc = try fixture.file("Documents", "notes.txt")
            XCTAssertNotNil(validator.validate(target: doc, root: root).failure, rule.id)
        }
    }

    func testFriendlyDerivedDataNames() {
        XCTAssertEqual(PathDisplay.friendlyName(for: "MyApp-bxkqzflcmwzrjvgdyxhuyfbpqkts", ruleID: CleanupRuleRegistry.ID.xcodeDerivedData), "MyApp")
        XCTAssertEqual(PathDisplay.friendlyName(for: "ModuleCache.noindex", ruleID: CleanupRuleRegistry.ID.xcodeDerivedData), "ModuleCache.noindex")
        XCTAssertEqual(PathDisplay.friendlyName(for: "MyApp-bxkqzflcmwzrjvgdyxhuyfbpqkts", ruleID: CleanupRuleRegistry.ID.npmCache), "MyApp-bxkqzflcmwzrjvgdyxhuyfbpqkts")
    }

    func testShortenedPathsHideHome() {
        let home = URL(fileURLWithPath: "/Users/tester")
        XCTAssertEqual(PathDisplay.shortened(URL(fileURLWithPath: "/Users/tester/Library/Caches/Yarn"), home: home), "~/Library/Caches/Yarn")
        XCTAssertEqual(PathDisplay.shortened(URL(fileURLWithPath: "/Users/tester2/x"), home: home), "/Users/tester2/x")
    }
}
