import Foundation

actor ResidueScanner {
    private struct SearchRoot {
        let url: URL
        let category: ResidueCategory
        let requiresAdministrator: Bool
        let maximumDepth: Int
    }

    private let fileManager = FileManager.default

    func scan(_ application: InstalledApplication) -> ScanReport {
        var candidates: [ResidueCandidate] = []
        var seen = Set<String>()

        if application.isCurrentApplication {
            let ownSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SwiftUninstall", isDirectory: true)
            if fileManager.fileExists(atPath: ownSupport.path) {
                seen.insert(ownSupport.standardizedFileURL.path)
                candidates.append(ResidueCandidate(
                    url: ownSupport,
                    category: .applicationSupport,
                    confidence: .certain,
                    reason: "卸载器自身的数据与卸载记录",
                    allocatedSize: allocatedSize(of: ownSupport),
                    requiresAdministrator: false,
                    isSelected: true
                ))
            }
        }

        for child in managedContainerURLs(for: application) {
            guard fileManager.fileExists(atPath: child.path),
                  let result = ResidueMatcher.match(url: child, application: application) else { continue }
            let key = child.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue }
            candidates.append(ResidueCandidate(
                url: child,
                category: .container,
                confidence: result.confidence,
                reason: result.reason,
                allocatedSize: allocatedSize(of: child),
                requiresAdministrator: false,
                isSelected: result.confidence >= .likely
            ))
        }

        for root in searchRoots(for: application) where fileManager.fileExists(atPath: root.url.path) {
            let children: [URL]
            guard let listed = try? fileManager.contentsOfDirectory(
                at: root.url,
                includingPropertiesForKeys: nil,
                options: []
            ) else { continue }
            children = listed

            for child in children {
                guard child.standardizedFileURL != application.url.standardizedFileURL,
                      let result = ResidueMatcher.match(url: child, application: application) else {
                    continue
                }
                let key = child.standardizedFileURL.path
                guard seen.insert(key).inserted else { continue }
                candidates.append(ResidueCandidate(
                    url: child,
                    category: root.category,
                    confidence: result.confidence,
                    reason: result.reason,
                    allocatedSize: allocatedSize(of: child),
                    requiresAdministrator: root.requiresAdministrator,
                    isSelected: result.confidence >= .likely
                ))
            }
        }

        candidates.append(contentsOf: matchingReceipts(for: application))
        candidates.append(ResidueCandidate(
            url: application.url,
            category: .application,
            confidence: .certain,
            reason: "应用本体",
            allocatedSize: max(application.installedSize, allocatedSize(of: application.url)),
            requiresAdministrator: !fileManager.isWritableFile(atPath: application.url.deletingLastPathComponent().path),
            isSelected: true
        ))

        candidates.sort {
            if $0.category == $1.category { return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            return $0.category.rawValue < $1.category.rawValue
        }
        return ScanReport(application: application, createdAt: Date(), candidates: candidates)
    }

    private func searchRoots(for application: InstalledApplication) -> [SearchRoot] {
        let home = fileManager.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)
        var roots = [
            SearchRoot(url: library.appendingPathComponent("Application Support"), category: .applicationSupport, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("Application Support/CrashReporter"), category: .log, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("Caches"), category: .cache, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("Preferences"), category: .preference, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("Preferences/ByHost"), category: .preference, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("Saved Application State"), category: .savedState, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("HTTPStorages"), category: .webData, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("WebKit"), category: .webData, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("Logs"), category: .log, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("Logs/DiagnosticReports"), category: .log, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("LaunchAgents"), category: .launchItem, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("QuickLook"), category: .other, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("PreferencePanes"), category: .other, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("Services"), category: .other, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("Input Methods"), category: .other, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("Screen Savers"), category: .other, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: library.appendingPathComponent("Internet Plug-Ins"), category: .other, requiresAdministrator: false, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/Application Support"), category: .applicationSupport, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/Application Support/CrashReporter"), category: .log, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/Caches"), category: .cache, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/Preferences"), category: .preference, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/Preferences/ByHost"), category: .preference, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/Logs"), category: .log, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"), category: .log, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/LaunchAgents"), category: .launchItem, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/LaunchDaemons"), category: .launchItem, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/PrivilegedHelperTools"), category: .privilegedHelper, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/Extensions"), category: .privilegedHelper, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/QuickLook"), category: .other, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/PreferencePanes"), category: .other, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/Services"), category: .other, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/Input Methods"), category: .other, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/Screen Savers"), category: .other, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Library/Internet Plug-Ins"), category: .other, requiresAdministrator: true, maximumDepth: 1),
            SearchRoot(url: URL(fileURLWithPath: "/Users/Shared"), category: .sharedData, requiresAdministrator: true, maximumDepth: 1)
        ]
        roots.append(contentsOf: vendorNestedRoots(
            base: library.appendingPathComponent("Application Support"),
            application: application,
            requiresAdministrator: false
        ))
        roots.append(contentsOf: vendorNestedRoots(
            base: URL(fileURLWithPath: "/Library/Application Support"),
            application: application,
            requiresAdministrator: true
        ))
        return roots
    }

    private func vendorNestedRoots(
        base: URL,
        application: InstalledApplication,
        requiresAdministrator: Bool
    ) -> [SearchRoot] {
        guard let bundleID = application.bundleIdentifier else { return [] }
        let ignored = Set(["com", "org", "net", "io", "co", "app", "mac", "macos"])
        let product = ResidueMatcher.normalized(application.name)
        let tokens = Set(bundleID.split(separator: ".").map { ResidueMatcher.normalized(String($0)) })
            .filter { $0.count >= 3 && !ignored.contains($0) && $0 != product }
        guard !tokens.isEmpty,
              let directories = try? fileManager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return [] }
        return directories.compactMap { directory in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  tokens.contains(ResidueMatcher.normalized(directory.lastPathComponent)) else { return nil }
            return SearchRoot(
                url: directory,
                category: .applicationSupport,
                requiresAdministrator: requiresAdministrator,
                maximumDepth: 1
            )
        }
    }

    private func managedContainerURLs(for application: InstalledApplication) -> [URL] {
        guard let bundleID = application.bundleIdentifier else { return [] }
        let library = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let roots = ["Containers", "Group Containers", "Application Scripts"].map {
            library.appendingPathComponent($0, isDirectory: true)
        }
        var names = [bundleID, "group.\(bundleID)"]
        if let teamID = application.teamIdentifier {
            names.append("\(teamID).\(bundleID)")
        }
        var urls = roots.flatMap { root in names.map { root.appendingPathComponent($0, isDirectory: true) } }

        let escapedBundleID = bundleID.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let query = "kMDItemFSName == \"*\(escapedBundleID)*\"cd"
        for root in roots where fileManager.fileExists(atPath: root.path) {
            urls.append(contentsOf: spotlightPaths(in: root, query: query, timeout: 1.5))
        }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func spotlightPaths(in directory: URL, query: String, timeout: TimeInterval) -> [URL] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", directory.path, query]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.split(separator: "\n").map {
            URL(fileURLWithPath: String($0))
        }
    }

    private func matchingReceipts(for application: InstalledApplication) -> [ResidueCandidate] {
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
        return output.split(separator: "\n").compactMap { line in
            let identifier = String(line)
            guard let result = ResidueMatcher.receiptMatches(identifier, application: application) else { return nil }
            return ResidueCandidate(receiptIdentifier: identifier, confidence: result.confidence, reason: result.reason)
        }
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
