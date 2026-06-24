import Foundation

actor OrphanScanner {
    private struct ScanRoot {
        let url: URL
        let category: ResidueCategory
        let requiresAdministrator: Bool
        let confidence: MatchConfidence
    }

    private let fileManager = FileManager.default

    private let systemPrefixes = ["com.apple.", "com.apple", "."]
    private let systemNames: Set<String> = [
        "CrashReporter", "Metadata", "CloudKit", "AddressBook", "CallHistoryDB",
        "FaceTime", "CloudDocs", "Knowledge", "Suggestions", "Siri", "Safari",
        "Notes", "Mail", "Messages", "Maps", "Calendar", "Reminders", "Stocks",
        "News", "Home", "iTunes", "QuickLook", "Dock", "loginwindow",
        "Group Containers", "Application Scripts", "Mobile Documents",
        "AssistantServices", "FontRegistry", "Caches", "Preferences",
        "com.apple.shared", "CoreSimulator", "FontRegistrationAgent"
    ]

    func scan(installedApplications: [InstalledApplication]) -> [ResidueCandidate] {
        guard !installedApplications.isEmpty else { return [] }
        let ownership = OwnershipIndex(applications: installedApplications)
        var candidates: [ResidueCandidate] = []
        var seen = Set<String>()

        candidates.append(contentsOf: orphanReceipts(ownership: ownership, seen: &seen))

        let home = fileManager.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)

        for root in scanRoots(userLibrary: library) where fileManager.fileExists(atPath: root.url.path) {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root.url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children {
                guard !isSystemItem(child.lastPathComponent) else { continue }
                let key = child.standardizedFileURL.path
                guard seen.insert(key).inserted, !ownership.owns(url: child) else { continue }
                candidates.append(ResidueCandidate(
                    url: child,
                    category: root.category,
                    confidence: root.confidence,
                    reason: "位于残留目录且未匹配到已安装应用",
                    allocatedSize: allocatedSize(of: child),
                    requiresAdministrator: root.requiresAdministrator,
                    isSelected: root.confidence >= .likely
                ))
            }
        }

        candidates.sort {
            if $0.category == $1.category {
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            return $0.category.rawValue < $1.category.rawValue
        }
        return candidates
    }

    private func scanRoots(userLibrary: URL) -> [ScanRoot] {
        [
            ScanRoot(url: userLibrary.appendingPathComponent("LaunchAgents"), category: .launchItem, requiresAdministrator: false, confidence: .likely),
            ScanRoot(url: userLibrary.appendingPathComponent("Application Support"), category: .applicationSupport, requiresAdministrator: false, confidence: .possible),
            ScanRoot(url: userLibrary.appendingPathComponent("Caches"), category: .cache, requiresAdministrator: false, confidence: .possible),
            ScanRoot(url: userLibrary.appendingPathComponent("Preferences"), category: .preference, requiresAdministrator: false, confidence: .possible),
            ScanRoot(url: userLibrary.appendingPathComponent("Saved Application State"), category: .savedState, requiresAdministrator: false, confidence: .possible),
            ScanRoot(url: userLibrary.appendingPathComponent("PreferencePanes"), category: .other, requiresAdministrator: false, confidence: .possible),
            ScanRoot(url: userLibrary.appendingPathComponent("HTTPStorages"), category: .webData, requiresAdministrator: false, confidence: .possible),
            ScanRoot(url: userLibrary.appendingPathComponent("WebKit"), category: .webData, requiresAdministrator: false, confidence: .possible),
            ScanRoot(url: userLibrary.appendingPathComponent("Logs"), category: .log, requiresAdministrator: false, confidence: .possible),
            ScanRoot(url: URL(fileURLWithPath: "/Library/Application Support"), category: .applicationSupport, requiresAdministrator: true, confidence: .likely),
            ScanRoot(url: URL(fileURLWithPath: "/Library/LaunchAgents"), category: .launchItem, requiresAdministrator: true, confidence: .likely),
            ScanRoot(url: URL(fileURLWithPath: "/Library/LaunchDaemons"), category: .launchItem, requiresAdministrator: true, confidence: .likely),
            ScanRoot(url: URL(fileURLWithPath: "/Library/PrivilegedHelperTools"), category: .privilegedHelper, requiresAdministrator: true, confidence: .likely),
            ScanRoot(url: URL(fileURLWithPath: "/Library/PreferencePanes"), category: .other, requiresAdministrator: true, confidence: .possible)
        ]
    }

    private func orphanReceipts(ownership: OwnershipIndex, seen: inout Set<String>) -> [ResidueCandidate] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = ["--pkgs"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return [] }
        var result: [ResidueCandidate] = []
        for line in output.split(separator: "\n") {
            let id = String(line)
            guard !isSystemItem(id), !ownership.ownsReceipt(id) else { continue }
            seen.insert("receipt:\(id)")
            result.append(ResidueCandidate(receiptIdentifier: id, confidence: .likely, reason: "安装收据未匹配到已安装应用"))
        }
        return result
    }

    private func isSystemItem(_ name: String) -> Bool {
        let lower = name.lowercased()
        if systemPrefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        return systemNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]) else { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return 0 }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
              let kilobytes = Int64(output.split(whereSeparator: { $0 == " " || $0 == "\t" }).first ?? "") else { return 0 }
        return kilobytes * 1_024
    }
}

private struct OwnershipIndex {
    let bundleIdentifiers: [String]
    let nameTokens: Set<String>
    let executableTokens: Set<String>

    init(applications: [InstalledApplication]) {
        var bids: [String] = []
        var names = Set<String>()
        var exes = Set<String>()
        for app in applications {
            if let id = app.bundleIdentifier?.lowercased(), !id.isEmpty { bids.append(id) }
            let name = ResidueMatcher.normalized(app.name)
            if name.count >= 4 { names.insert(name) }
            let exe = ResidueMatcher.normalized(app.executableName ?? "")
            if exe.count >= 5 { exes.insert(exe) }
        }
        self.bundleIdentifiers = bids
        self.nameTokens = names
        self.executableTokens = exes
    }

    func owns(url: URL) -> Bool {
        let filename = url.lastPathComponent.lowercased()
        for bid in bundleIdentifiers where !bid.isEmpty {
            if filename.contains(bid) { return true }
        }
        let normalized = ResidueMatcher.normalized(filename)
        if nameTokens.contains(normalized) { return true }
        for token in nameTokens where token.count >= 5 && normalized.hasPrefix(token) { return true }
        for token in executableTokens where token.count >= 5 && normalized.hasPrefix(token) { return true }
        return false
    }

    func ownsReceipt(_ id: String) -> Bool {
        let receipt = id.lowercased()
        for bid in bundleIdentifiers where !bid.isEmpty {
            if receipt == bid || receipt.hasPrefix(bid + ".") { return true }
        }
        let normalized = ResidueMatcher.normalized(receipt)
        for token in nameTokens where token.count >= 5 && normalized.contains(token) { return true }
        return false
    }
}
