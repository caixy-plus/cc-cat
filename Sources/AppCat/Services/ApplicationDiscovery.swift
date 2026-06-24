import AppKit
import Foundation
import Security

actor ApplicationDiscovery {
    private let fileManager = FileManager.default

    func discoverApplications() -> [InstalledApplication] {
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]

        var seen = Set<String>()
        var applications: [InstalledApplication] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                let path = url.standardizedFileURL.path
                guard seen.insert(path).inserted,
                      let application = makeApplication(at: url) else { continue }
                applications.append(application)
            }
        }

        return applications.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func makeApplication(at url: URL) -> InstalledApplication? {
        guard let bundle = Bundle(url: url) else { return nil }
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        return InstalledApplication(
            url: url,
            name: (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundle.bundleIdentifier,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            executableName: bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
            teamIdentifier: signingTeamIdentifier(for: url),
            installedSize: Int64(values?.totalFileAllocatedSize ?? 0),
            isSystemApplication: url.path.hasPrefix("/System/")
        )
    }

    private func signingTeamIdentifier(for url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [CFString: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier] as? String
    }
}

