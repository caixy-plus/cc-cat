import XCTest
@testable import AppCat

final class OrphanScannerTests: XCTestCase {
    func testScanCompletesWithoutFlaggingInstalledApps() async {
        let apps = await ApplicationDiscovery().discoverApplications()
        XCTAssertFalse(apps.isEmpty, "需要至少一个已安装应用才能评估归属")

        let scanner = OrphanScanner()
        let candidates = await scanner.scan(installedApplications: apps)

        let installedNames = Set(apps.compactMap { ResidueMatcher.normalized($0.name) })
        for candidate in candidates where candidate.url != nil {
            let name = ResidueMatcher.normalized(candidate.displayName)
            XCTAssertFalse(
                installedNames.contains(name),
                "已安装应用 \(candidate.displayName) 不应被标记为孤儿残留"
            )
        }
        XCTAssertFalse(candidates.contains { $0.displayName.isEmpty })
    }

    func testReceiptsOnlyContainNonAppleOrphans() async {
        let apps = await ApplicationDiscovery().discoverApplications()
        let candidates = await OrphanScanner().scan(installedApplications: apps)
        for candidate in candidates where candidate.receiptIdentifier != nil {
            XCTAssertFalse(candidate.receiptIdentifier!.lowercased().hasPrefix("com.apple."))
        }
    }
}
