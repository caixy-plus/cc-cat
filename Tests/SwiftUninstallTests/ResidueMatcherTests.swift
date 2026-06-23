import XCTest
@testable import SwiftUninstall

final class ResidueMatcherTests: XCTestCase {
    private let application = InstalledApplication(
        url: URL(fileURLWithPath: "/Applications/Example Cleaner.app"),
        name: "Example Cleaner",
        bundleIdentifier: "com.example.cleaner",
        version: "1.0",
        executableName: "ExampleCleaner",
        teamIdentifier: "TEAM123",
        installedSize: 100,
        isSystemApplication: false
    )

    func testBundleIdentifierIsCertain() {
        let url = URL(fileURLWithPath: "/Users/me/Library/Caches/com.example.cleaner")
        XCTAssertEqual(ResidueMatcher.match(url: url, application: application)?.confidence, .certain)
    }

    func testExactApplicationNameIsLikely() {
        let url = URL(fileURLWithPath: "/Users/me/Library/Application Support/Example Cleaner")
        XCTAssertEqual(ResidueMatcher.match(url: url, application: application)?.confidence, .likely)
    }

    func testUnrelatedPathDoesNotMatch() {
        let url = URL(fileURLWithPath: "/Users/me/Library/Caches/com.example.other")
        XCTAssertNil(ResidueMatcher.match(url: url, application: application))
    }

    func testReceiptBundleIdentifierIsCertain() {
        XCTAssertEqual(
            ResidueMatcher.receiptMatches("com.example.cleaner.pkg", application: application)?.confidence,
            .certain
        )
    }

    func testGlobalPreferenceReferencingApplicationIsNotAResidue() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preference = directory.appendingPathComponent("com.apple.dock.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["recent-app": application.url.path],
            format: .xml,
            options: 0
        )
        try data.write(to: preference)
        XCTAssertNil(ResidueMatcher.match(url: preference, application: application))
    }

    func testLaunchAgentReferencingApplicationIsCertain() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let launchAgent = directory.appendingPathComponent("helper.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["Program": application.url.path],
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgent)
        XCTAssertEqual(ResidueMatcher.match(url: launchAgent, application: application)?.confidence, .certain)
    }
}
