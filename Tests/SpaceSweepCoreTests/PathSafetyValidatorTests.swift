import XCTest
@testable import SpaceSweepCore

final class PathSafetyValidatorTests: XCTestCase {
    var fixture: Fixture!
    var validator: PathSafetyValidator!
    var root: URL!

    override func setUpWithError() throws {
        fixture = try Fixture()
        validator = PathSafetyValidator(environment: fixture.environment)
        root = try fixture.dir("Library", "Developer", "Xcode", "DerivedData")
    }

    override func tearDown() { fixture = nil }

    // 1
    func testValidTargetInsideRootIsAccepted() throws {
        let target = try fixture.dir("Library", "Developer", "Xcode", "DerivedData", "MyApp-abc")
        guard case .success(let fingerprint) = validator.validate(target: target, root: root) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(fingerprint.kind, .directory)
    }

    // 2
    func testRootItselfIsRejected() {
        XCTAssertEqual(validator.lexicalFailure(target: root, root: root), .isRootItself)
        XCTAssertEqual(validator.validate(target: root, root: root).failure, .isRootItself)
        XCTAssertEqual(validator.validate(target: root.appendingPathComponent("/"), root: root).failure, .isRootItself)
    }

    // 3
    func testParentTraversalIsRejected() throws {
        try fixture.dir("Documents", "Project")
        let traversal = root.appendingPathComponent("..").appendingPathComponent("..")
            .appendingPathComponent("..").appendingPathComponent("..").appendingPathComponent("Documents")
        XCTAssertEqual(validator.validate(target: traversal, root: root).failure, .containsTraversal)
        let dot = root.appendingPathComponent(".").appendingPathComponent("x")
        XCTAssertEqual(validator.lexicalFailure(target: dot, root: root), .containsTraversal)
    }

    // 4
    func testSimilarPrefixIsRejected() throws {
        let evil = try fixture.dir("Library", "Developer", "Xcode", "DerivedData-evil", "payload")
        XCTAssertEqual(validator.validate(target: evil, root: root).failure, .notInsideRoot)
        XCTAssertFalse(PathSafetyValidator.isSameOrInside(URL(fileURLWithPath: "/allowed/root-evil"),
                                                          URL(fileURLWithPath: "/allowed/root")))
        XCTAssertTrue(PathSafetyValidator.isSameOrInside(URL(fileURLWithPath: "/allowed/root/child"),
                                                         URL(fileURLWithPath: "/allowed/root")))
    }

    // 5
    func testSymlinkPointingOutsideIsRejectedAndNotFollowed() throws {
        let precious = try fixture.file("precious.txt", from: fixture.outside)
        let link = try fixture.symlink("Library", "Developer", "Xcode", "DerivedData", "Link", to: fixture.outside)
        XCTAssertEqual(validator.validate(target: link, root: root).failure, .symbolicLink)
        // A path *through* the link resolves outside the root.
        let through = link.appendingPathComponent("precious.txt")
        XCTAssertEqual(validator.validate(target: through, root: root).failure, .resolvesOutsideRoot)
        XCTAssertTrue(fixture.exists(precious))
    }

    func testRootThatIsASymlinkIsRejected() throws {
        let realCaches = try fixture.dir("RealYarn", from: fixture.outside)
        try fixture.file("v6", "pkg", from: realCaches)
        try fixture.dir("Library", "Caches")
        let linkedRoot = try fixture.symlink("Library", "Caches", "Yarn", to: realCaches)
        XCTAssertEqual(validator.validateRoot(linkedRoot).failure, .rootIsSymbolicLink)
        XCTAssertEqual(validator.validate(target: linkedRoot.appendingPathComponent("v6"), root: linkedRoot).failure,
                       .rootIsSymbolicLink)
    }

    func testRootReachedThroughSymlinkedAncestorIsRejected() throws {
        let elsewhere = try fixture.dir("Xcode", "DerivedData", "Proj", from: fixture.outside)
        _ = elsewhere
        try fixture.dir("Library", "Developer", "Xcode2")
        let ancestor = try fixture.symlink("Library", "Developer", "XcodeLinked", to: fixture.outside.appendingPathComponent("Xcode"))
        let root = ancestor.appendingPathComponent("DerivedData")
        XCTAssertEqual(validator.validateRoot(root).failure, .rootIsSymbolicLink)
    }

    // 7
    func testProtectedPathsAlwaysFail() throws {
        let live = PathSafetyValidator(environment: PathEnvironment(homeDirectory: URL(fileURLWithPath: "/Users/tester")))
        for path in ["/System/Library/Caches/x", "/private/var/vm/swapfile0", "/Library/Caches/com.apple.x",
                     "/usr/local/lib/x", "/Applications/Xcode.app", "/Volumes/External/x", "/var/folders/x",
                     "/Users/tester", "/Users/tester/Documents/Project/file.swift", "/Users/tester/.ssh/id_ed25519",
                     "/Users/tester/Library/Keychains/login.keychain-db", "/Users/tester/Library",
                     "/Users/tester/Library/Messages/chat.db", "/Users/tester/Library/Mail/V10",
                     "/Users/tester/Library/Application Support/MobileSync/Backup/abc",
                     "/Users/tester/Library/Developer/CoreSimulator/Devices/ABC", "/", "/Users"] {
            XCTAssertTrue(live.isProtected(URL(fileURLWithPath: path)), path)
        }
        XCTAssertFalse(live.isProtected(URL(fileURLWithPath: "/Users/tester/Library/Developer/Xcode/DerivedData/App-x")))

        // Even if a protected location were manually inserted as a "root", validation fails.
        let keychains = try fixture.dir("Library", "Keychains")
        let keychain = try fixture.file("Library", "Keychains", "login.keychain-db")
        XCTAssertEqual(validator.validate(target: keychain, root: keychains).failure, .protectedLocation)
        let documents = try fixture.dir("Documents")
        let doc = try fixture.file("Documents", "thesis.pages")
        XCTAssertEqual(validator.validate(target: doc, root: documents).failure, .protectedLocation)
        // Rooting a rule at the home directory is rejected.
        XCTAssertEqual(validator.validate(target: doc, root: fixture.home).failure, .notInsideRoot)
    }

    func testVersionControlDataIsRejected() throws {
        let git = try fixture.dir("Library", "Developer", "Xcode", "DerivedData", "Proj", ".git")
        XCTAssertEqual(validator.validate(target: git, root: root).failure, .versionControlData)
    }

    func testNonFileAndRelativeURLsAreRejected() {
        XCTAssertEqual(validator.lexicalFailure(target: URL(string: "https://example.com/x")!, root: root), .notAbsolute)
        XCTAssertEqual(validator.lexicalFailure(target: URL(string: "relative/path")!, root: root), .notAbsolute)
    }

    func testMissingTargetIsReported() {
        let ghost = root.appendingPathComponent("Ghost")
        XCTAssertEqual(validator.validate(target: ghost, root: root).failure, .missing)
    }

    func testFingerprintMismatchIsRejected() throws {
        let target = try fixture.dir("Library", "Developer", "Xcode", "DerivedData", "App-1")
        guard case .success(let original) = validator.validate(target: target, root: root) else { return XCTFail() }
        try FileManager.default.moveItem(at: target, to: fixture.outside.appendingPathComponent("moved"))
        try fixture.file("Library", "Developer", "Xcode", "DerivedData", "App-1")
        XCTAssertEqual(validator.validate(target: target, root: root, expected: original).failure, .changedSinceScan)
    }

    func testItemOwnedByAnotherUserIsRejected() throws {
        let other = try Fixture(userID: FileSystemProbe.currentUserID &+ 4242)
        let otherRoot = try other.dir("Library", "Developer", "Xcode", "DerivedData")
        let target = try other.dir("Library", "Developer", "Xcode", "DerivedData", "App")
        let otherValidator = PathSafetyValidator(environment: other.environment)
        XCTAssertEqual(otherValidator.validate(target: target, root: otherRoot).failure, .notOwnedByUser)
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
