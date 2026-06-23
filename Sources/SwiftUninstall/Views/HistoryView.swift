import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(state.history) { record in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.applicationName).fontWeight(.medium)
                        Text(record.date.formatted()).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: record.reclaimedBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                    Button("恢复") { Task { await state.restore(record) } }
                }
            }
            .overlay {
                if state.history.isEmpty {
                    ContentUnavailableView("暂无卸载记录", systemImage: "clock")
                }
            }
            .navigationTitle("卸载记录")
            .toolbar { Button("完成") { dismiss() } }
        }
        .frame(minWidth: 650, minHeight: 420)
    }
}

