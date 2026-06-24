import Foundation

struct RemovedItem: Codable, Hashable, Sendable {
    let originalURL: URL?
    let recoveryURL: URL?
    let receiptIdentifier: String?
    let removedAt: Date
}

struct UninstallRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let applicationName: String
    let bundleIdentifier: String?
    let date: Date
    let reclaimedBytes: Int64
    let items: [RemovedItem]
}

