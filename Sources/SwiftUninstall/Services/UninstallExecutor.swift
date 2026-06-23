import AppKit
import Foundation

enum UninstallError: LocalizedError {
    case nothingSelected
    case cannotCreateRecoveryDirectory
    case itemStillExists(String)

    var errorDescription: String? {
        switch self {
        case .nothingSelected: return "没有选择任何卸载项目"
        case .cannotCreateRecoveryDirectory: return "无法创建恢复目录"
        case .itemStillExists(let path): return "项目未能移除：\(path)"
        }
    }
}

actor UninstallExecutor {
    private let fileManager = FileManager.default
    private let administrator = AdministratorExecutor()
    private let history = HistoryStore()

    func uninstall(report: ScanReport) async throws -> UninstallRecord {
        let selected = report.candidates.filter(\.isSelected)
        guard !selected.isEmpty else { throw UninstallError.nothingSelected }

        let isSelfUninstall = report.application.isCurrentApplication
        if !isSelfUninstall {
            await terminate(application: report.application)
        }
        await unloadLaunchItems(in: selected)

        let recordID = UUID()
        let recoveryRoot = URL(fileURLWithPath: "/Users/Shared/SwiftUninstall Recovery", isDirectory: true)
            .appendingPathComponent(recordID.uuidString, isDirectory: true)

        var administratorCommands: [String] = []
        var plannedRecovery: [String: URL] = [:]

        for candidate in selected where candidate.requiresAdministrator {
            if let source = candidate.url {
                let destination = Self.administratorDestination(
                    for: source,
                    recoveryRoot: recoveryRoot,
                    recordID: recordID,
                    isSelfUninstall: isSelfUninstall,
                    homeDirectory: fileManager.homeDirectoryForCurrentUser
                )
                plannedRecovery[candidate.id] = destination
                administratorCommands.append("/bin/mkdir -p \(AdministratorExecutor.shellQuoted(destination.deletingLastPathComponent().path))")
                if candidate.category == .launchItem && source.path.contains("/LaunchDaemons/") {
                    administratorCommands.append("/bin/launchctl bootout system \(AdministratorExecutor.shellQuoted(source.path)) >/dev/null 2>&1 || true")
                }
                if source.pathExtension.lowercased() == "kext",
                   let bundleID = Bundle(url: source)?.bundleIdentifier {
                    administratorCommands.append("/usr/bin/kmutil unload -b \(AdministratorExecutor.shellQuoted(bundleID)) >/dev/null 2>&1 || true")
                }
                administratorCommands.append("/bin/mv -- \(AdministratorExecutor.shellQuoted(source.path)) \(AdministratorExecutor.shellQuoted(destination.path))")
            } else if let receipt = candidate.receiptIdentifier {
                administratorCommands.append("/usr/sbin/pkgutil --forget \(AdministratorExecutor.shellQuoted(receipt)) >/dev/null")
            }
        }

        try await administrator.run(commands: administratorCommands)

        var removed: [RemovedItem] = []
        var reclaimed: Int64 = 0

        for candidate in selected {
            if candidate.requiresAdministrator {
                if let source = candidate.url {
                    guard !fileManager.fileExists(atPath: source.path) else { throw UninstallError.itemStillExists(source.path) }
                    removed.append(RemovedItem(
                        originalURL: source,
                        recoveryURL: plannedRecovery[candidate.id],
                        receiptIdentifier: nil,
                        removedAt: Date()
                    ))
                } else {
                    removed.append(RemovedItem(
                        originalURL: nil,
                        recoveryURL: nil,
                        receiptIdentifier: candidate.receiptIdentifier,
                        removedAt: Date()
                    ))
                }
            } else if let source = candidate.url, fileManager.fileExists(atPath: source.path) {
                var trashURL: NSURL?
                try fileManager.trashItem(at: source, resultingItemURL: &trashURL)
                removed.append(RemovedItem(
                    originalURL: source,
                    recoveryURL: trashURL as URL?,
                    receiptIdentifier: nil,
                    removedAt: Date()
                ))
            }
            reclaimed += candidate.allocatedSize
        }

        let record = UninstallRecord(
            id: recordID,
            applicationName: report.application.name,
            bundleIdentifier: report.application.bundleIdentifier,
            date: Date(),
            reclaimedBytes: reclaimed,
            items: removed
        )
        if isSelfUninstall {
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    NSApplication.shared.terminate(nil)
                }
            }
        } else {
            try await history.append(record)
        }
        return record
    }

    func restore(_ record: UninstallRecord) async throws {
        var administratorCommands: [String] = []
        for item in record.items.reversed() {
            guard let original = item.originalURL, let recovery = item.recoveryURL,
                  fileManager.fileExists(atPath: recovery.path) else { continue }

            if recovery.path.hasPrefix("/Users/Shared/SwiftUninstall Recovery/") {
                administratorCommands.append("/bin/mkdir -p \(AdministratorExecutor.shellQuoted(original.deletingLastPathComponent().path))")
                administratorCommands.append("/bin/mv -- \(AdministratorExecutor.shellQuoted(recovery.path)) \(AdministratorExecutor.shellQuoted(original.path))")
            } else {
                try fileManager.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: recovery, to: original)
            }
        }
        try await administrator.run(commands: administratorCommands)
    }

    private func uniqueDestination(for source: URL, in directory: URL) -> URL {
        directory.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
    }

    static func administratorDestination(
        for source: URL,
        recoveryRoot: URL,
        recordID: UUID,
        isSelfUninstall: Bool,
        homeDirectory: URL
    ) -> URL {
        let sharedRecoveryBase = URL(fileURLWithPath: "/Users/Shared/SwiftUninstall Recovery", isDirectory: true)
        if isSelfUninstall,
           source.standardizedFileURL == sharedRecoveryBase.standardizedFileURL {
            return homeDirectory
                .appendingPathComponent(".Trash", isDirectory: true)
                .appendingPathComponent("SwiftUninstall Recovery-\(recordID.uuidString)", isDirectory: true)
        }
        return recoveryRoot.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
    }

    private func terminate(application: InstalledApplication) async {
        guard let bundleID = application.bundleIdentifier else { return }
        await MainActor.run {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            running.forEach { _ = $0.terminate() }
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await MainActor.run {
            let remaining = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            remaining.forEach { _ = $0.forceTerminate() }
        }
    }

    private func unloadLaunchItems(in candidates: [ResidueCandidate]) async {
        let uid = getuid()
        for candidate in candidates where candidate.category == .launchItem {
            guard let url = candidate.url else { continue }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            if url.path.contains("/LaunchDaemons/") {
                continue // The following administrator batch moves the daemon; it cannot relaunch after restart.
            } else {
                process.arguments = ["bootout", "gui/\(uid)", url.path]
            }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
}
