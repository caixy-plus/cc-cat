import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var applications: [InstalledApplication] = []
    @Published var selection: InstalledApplication.ID?
    @Published var searchText = ""
    @Published var candidates: [ResidueCandidate] = []
    @Published var isLoadingApplications = false
    @Published var isScanning = false
    @Published var isUninstalling = false
    @Published var errorMessage: String?
    @Published var completionMessage: String?
    @Published var history: [UninstallRecord] = []
    @Published var showsHistory = false
    @Published var orphanCandidates: [ResidueCandidate] = []
    @Published var isScanningOrphans = false
    @Published var showsOrphanScan = false

    private let discovery = ApplicationDiscovery()
    private let scanner = ResidueScanner()
    private let executor = UninstallExecutor()
    private let historyStore = HistoryStore()
    private let orphanScanner = OrphanScanner()

    var filteredApplications: [InstalledApplication] {
        guard !searchText.isEmpty else { return applications }
        return applications.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var selectedApplication: InstalledApplication? {
        applications.first { $0.id == selection }
    }

    var selectedSize: Int64 {
        candidates.filter(\.isSelected).reduce(0) { $0 + $1.allocatedSize }
    }

    var selectedOrphanSize: Int64 {
        orphanCandidates.filter(\.isSelected).reduce(0) { $0 + $1.allocatedSize }
    }

    init() {
        Task {
            await reloadApplications()
            await reloadHistory()
        }
    }

    func reloadApplications() async {
        isLoadingApplications = true
        applications = await discovery.discoverApplications()
        if selection == nil { selection = applications.first?.id }
        isLoadingApplications = false
    }

    func scanSelectedApplication() async {
        guard let application = selectedApplication else { return }
        isScanning = true
        errorMessage = nil
        let report = await scanner.scan(application)
        guard selection == application.id else {
            isScanning = false
            return
        }
        candidates = report.candidates
        isScanning = false
    }

    func uninstallSelectedItems() async {
        guard let application = selectedApplication else { return }
        isUninstalling = true
        errorMessage = nil
        do {
            let report = ScanReport(application: application, createdAt: Date(), candidates: candidates)
            let record = try await executor.uninstall(report: report)
            completionMessage = "已卸载 \(record.applicationName)，处理 \(record.items.count) 个项目"
            candidates = []
            selection = nil
            await reloadApplications()
            await reloadHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
        isUninstalling = false
    }

    func scanOrphans() async {
        isScanningOrphans = true
        errorMessage = nil
        orphanCandidates = await orphanScanner.scan(installedApplications: applications)
        isScanningOrphans = false
    }

    func cleanupSelectedOrphans() async {
        guard orphanCandidates.contains(where: \.isSelected) else { return }
        isUninstalling = true
        errorMessage = nil
        do {
            let placeholder = InstalledApplication(
                url: URL(fileURLWithPath: "/"),
                name: "孤儿残留",
                bundleIdentifier: nil,
                version: nil,
                executableName: nil,
                teamIdentifier: nil,
                installedSize: 0,
                isSystemApplication: false
            )
            let report = ScanReport(application: placeholder, createdAt: Date(), candidates: orphanCandidates)
            let record = try await executor.uninstall(report: report)
            completionMessage = "已清理 \(record.items.count) 项残留"
            orphanCandidates = []
            await reloadHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
        isUninstalling = false
    }

    func selectRecommendedOrphans() {
        for index in orphanCandidates.indices {
            orphanCandidates[index].isSelected = orphanCandidates[index].confidence >= .likely
        }
    }

    func restore(_ record: UninstallRecord) async {
        do {
            try await executor.restore(record)
            completionMessage = "已恢复 \(record.applicationName) 的可恢复项目"
            await reloadApplications()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectCertainItems() {
        for index in candidates.indices {
            candidates[index].isSelected = candidates[index].confidence == .certain
        }
    }

    func selectRecommendedItems() {
        for index in candidates.indices {
            candidates[index].isSelected = candidates[index].confidence >= .likely
        }
    }

    private func reloadHistory() async {
        history = await historyStore.load()
    }
}

