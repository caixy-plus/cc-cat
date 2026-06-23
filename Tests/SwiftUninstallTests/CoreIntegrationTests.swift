import XCTest
@testable import SwiftUninstall

final class CoreIntegrationTests: XCTestCase {
    func testDiscoversInstalledApplicationsWithMetadata() async {
        let applications = await ApplicationDiscovery().discoverApplications()
        XCTAssertFalse(applications.isEmpty)
        XCTAssertTrue(applications.contains { $0.url.path.hasPrefix("/Applications/") })
        XCTAssertTrue(applications.contains { $0.bundleIdentifier != nil })
    }

    func testLiveScanAlwaysIncludesSelectedApplication() async throws {
        let applications = await ApplicationDiscovery().discoverApplications()
        let application = try XCTUnwrap(applications.first { $0.bundleIdentifier != nil })
        let report = await ResidueScanner().scan(application)
        let applicationCandidate = report.candidates.first {
            $0.category == .application && $0.url == application.url
        }
        XCTAssertEqual(applicationCandidate?.confidence, .certain)
        XCTAssertEqual(applicationCandidate?.isSelected, true)
    }

    func testCurrentApplicationCanIdentifyItself() {
        let bundle = Bundle.main
        let application = InstalledApplication(
            url: bundle.bundleURL,
            name: "应用卸载器",
            bundleIdentifier: bundle.bundleIdentifier,
            version: nil,
            executableName: nil,
            teamIdentifier: nil,
            installedSize: 0,
            isSystemApplication: false
        )
        XCTAssertTrue(application.isCurrentApplication)
    }

    func testSelfUninstallMovesSharedRecoveryOutsideItself() {
        let source = URL(fileURLWithPath: "/Users/Shared/SwiftUninstall Recovery", isDirectory: true)
        let recordID = UUID()
        let destination = UninstallExecutor.administratorDestination(
            for: source,
            recoveryRoot: source.appendingPathComponent(recordID.uuidString),
            recordID: recordID,
            isSelfUninstall: true,
            homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true)
        )
        XCTAssertTrue(destination.path.hasPrefix("/Users/test/.Trash/"))
        XCTAssertFalse(destination.path.hasPrefix(source.path + "/"))
    }
}
