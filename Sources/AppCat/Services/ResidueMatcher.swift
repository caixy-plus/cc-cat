import Foundation

struct MatchResult: Sendable {
    let confidence: MatchConfidence
    let reason: String
}

enum ResidueMatcher {
    static func match(url: URL, application: InstalledApplication) -> MatchResult? {
        let filename = url.lastPathComponent.lowercased()
        let path = url.path.lowercased()

        if let bundleID = application.bundleIdentifier?.lowercased(), !bundleID.isEmpty {
            let bundleExtensions: Set<String> = ["app", "appex", "xpc", "bundle", "plugin", "kext", "systemextension"]
            if bundleExtensions.contains(url.pathExtension.lowercased()),
               let embeddedBundleID = Bundle(url: url)?.bundleIdentifier?.lowercased(),
               embeddedBundleID == bundleID || embeddedBundleID.hasPrefix(bundleID + ".") {
                return MatchResult(confidence: .certain, reason: "组件 Bundle ID 属于该应用")
            }
            if filename.contains(bundleID) {
                return MatchResult(confidence: .certain, reason: "文件名包含 Bundle ID")
            }
            let isLaunchConfiguration = path.contains("/launchagents/") || path.contains("/launchdaemons/")
            if isLaunchConfiguration,
               metadataFile(at: url, references: [bundleID, application.url.path.lowercased()]) {
                return MatchResult(confidence: .certain, reason: "启动项或配置内容指向该应用")
            }
        }

        let name = normalized(application.name)
        let executable = normalized(application.executableName ?? "")
        let normalizedFilename = normalized(filename)

        if name.count >= 4 && normalizedFilename == name {
            return MatchResult(confidence: .likely, reason: "文件名与应用名称完全一致")
        }
        if name.count >= 5 && normalizedFilename.hasPrefix(name) {
            return MatchResult(confidence: .likely, reason: "文件名以应用名称开头")
        }
        if executable.count >= 5 && normalizedFilename.hasPrefix(executable) {
            return MatchResult(confidence: .likely, reason: "文件名与可执行文件名称匹配")
        }
        if name.count >= 6 && path.contains("/\(name)") {
            return MatchResult(confidence: .possible, reason: "路径包含应用名称")
        }
        return nil
    }

    static func receiptMatches(_ identifier: String, application: InstalledApplication) -> MatchResult? {
        let receipt = identifier.lowercased()
        if let bundleID = application.bundleIdentifier?.lowercased(), receipt == bundleID || receipt.hasPrefix(bundleID + ".") {
            return MatchResult(confidence: .certain, reason: "安装收据与 Bundle ID 一致")
        }
        let name = normalized(application.name)
        if name.count >= 5 && normalized(receipt).contains(name) {
            return MatchResult(confidence: .possible, reason: "安装收据名称与应用相似")
        }
        return nil
    }

    static func normalized(_ value: String) -> String {
        String(value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static func metadataFile(at url: URL, references needles: [String]) -> Bool {
        let extensions = ["plist", "json", "conf", "ini"]
        let fileExtension = url.pathExtension.lowercased()
        guard extensions.contains(fileExtension),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) < 1_000_000,
              let data = try? Data(contentsOf: url) else { return false }
        let text: String
        if fileExtension == "plist",
           let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            text = String(describing: propertyList).lowercased()
        } else if let decoded = String(data: data, encoding: .utf8)?.lowercased() {
            text = decoded
        } else {
            return false
        }
        return needles.contains { !$0.isEmpty && text.contains($0) }
    }
}
