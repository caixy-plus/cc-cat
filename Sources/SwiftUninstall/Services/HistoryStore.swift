import Foundation

actor HistoryStore {
    private let fileManager = FileManager.default
    private let recordsURL: URL

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwiftUninstall", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        recordsURL = base.appendingPathComponent("UninstallHistory.json")
    }

    func load() -> [UninstallRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: recordsURL),
              let records = try? decoder.decode([UninstallRecord].self, from: data) else { return [] }
        return records.sorted { $0.date > $1.date }
    }

    func append(_ record: UninstallRecord) throws {
        var records = load()
        records.insert(record, at: 0)
        let data = try JSONEncoder.pretty.encode(records)
        try data.write(to: recordsURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
