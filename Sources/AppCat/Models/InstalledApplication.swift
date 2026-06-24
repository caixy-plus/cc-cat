import Foundation

struct InstalledApplication: Identifiable, Hashable, Codable, Sendable {
    var id: String { url.path }

    let url: URL
    let name: String
    let bundleIdentifier: String?
    let version: String?
    let executableName: String?
    let teamIdentifier: String?
    let installedSize: Int64
    let isSystemApplication: Bool

    var isCurrentApplication: Bool {
        guard bundleIdentifier == Bundle.main.bundleIdentifier else { return false }
        return url.resolvingSymlinksInPath().standardizedFileURL
            == Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    }
}
