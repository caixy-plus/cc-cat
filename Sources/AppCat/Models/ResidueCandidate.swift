import Foundation

enum ResidueCategory: String, CaseIterable, Codable, Sendable {
    case application = "应用本体"
    case applicationSupport = "应用数据"
    case cache = "缓存"
    case preference = "偏好设置"
    case container = "沙盒容器"
    case savedState = "窗口状态"
    case webData = "网络数据"
    case log = "日志"
    case launchItem = "启动项"
    case privilegedHelper = "特权组件"
    case sharedData = "共享数据"
    case packageReceipt = "安装收据"
    case other = "其他"
}

enum MatchConfidence: Int, Codable, Comparable, Sendable {
    case possible = 40
    case likely = 70
    case certain = 100

    static func < (lhs: MatchConfidence, rhs: MatchConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .certain: return "确定相关"
        case .likely: return "高度相关"
        case .possible: return "可能相关"
        }
    }
}

struct ResidueCandidate: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let url: URL?
    let receiptIdentifier: String?
    let category: ResidueCategory
    let confidence: MatchConfidence
    let reason: String
    let allocatedSize: Int64
    let requiresAdministrator: Bool
    var isSelected: Bool

    init(
        url: URL,
        category: ResidueCategory,
        confidence: MatchConfidence,
        reason: String,
        allocatedSize: Int64,
        requiresAdministrator: Bool,
        isSelected: Bool
    ) {
        self.id = "file:\(url.standardizedFileURL.path)"
        self.url = url
        self.receiptIdentifier = nil
        self.category = category
        self.confidence = confidence
        self.reason = reason
        self.allocatedSize = allocatedSize
        self.requiresAdministrator = requiresAdministrator
        self.isSelected = isSelected
    }

    init(receiptIdentifier: String, confidence: MatchConfidence, reason: String) {
        self.id = "receipt:\(receiptIdentifier)"
        self.url = nil
        self.receiptIdentifier = receiptIdentifier
        self.category = .packageReceipt
        self.confidence = confidence
        self.reason = reason
        self.allocatedSize = 0
        self.requiresAdministrator = true
        self.isSelected = confidence == .certain
    }

    var displayName: String {
        url?.lastPathComponent ?? receiptIdentifier ?? id
    }
}

struct ScanReport: Codable, Sendable {
    let application: InstalledApplication
    let createdAt: Date
    var candidates: [ResidueCandidate]

    var selectedSize: Int64 {
        candidates.filter(\.isSelected).reduce(0) { $0 + $1.allocatedSize }
    }
}

