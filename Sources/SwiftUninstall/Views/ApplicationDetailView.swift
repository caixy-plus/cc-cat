import SwiftUI

struct ApplicationDetailView: View {
    @EnvironmentObject private var state: AppState
    let application: InstalledApplication
    @State private var confirmsUninstall = false

    private var groupedCandidates: [(ResidueCategory, [ResidueCandidate])] {
        Dictionary(grouping: state.candidates, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.0.rawValue < $1.0.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.isScanning {
                Spacer()
                ProgressView("正在分析应用及关联文件…")
                Spacer()
            } else if state.candidates.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "准备卸载 \(application.name)",
                    systemImage: "trash.square",
                    description: Text("先扫描应用本体及关联残留；扫描过程不会修改文件")
                )
                Button("扫描卸载项目") { Task { await state.scanSelectedApplication() } }
                    .buttonStyle(.borderedProminent)
                Spacer()
            } else {
                candidateList
                Divider()
                actionBar
            }
        }
        .confirmationDialog(
            "确认卸载 \(application.name)？",
            isPresented: $confirmsUninstall,
            titleVisibility: .visible
        ) {
            Button("卸载所选项目", role: .destructive) {
                Task { await state.uninstallSelectedItems() }
            }
        } message: {
            if application.isCurrentApplication {
                Text("应用卸载器会将自身及自身数据移入废纸篓，然后自动退出。")
            } else {
                Text("普通项目会移入废纸篓；系统项目会移入恢复区。此操作可能请求一次管理员授权。")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("要卸载的应用")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(application.name).font(.title2).fontWeight(.semibold)
                Text(application.bundleIdentifier ?? "无 Bundle ID")
                    .font(.callout).foregroundStyle(.secondary)
                Text(application.url.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Button("重新扫描卸载项目") { Task { await state.scanSelectedApplication() } }
                .disabled(state.isScanning || state.isUninstalling)
        }
        .padding(20)
    }

    private var candidateList: some View {
        List {
            ForEach(groupedCandidates, id: \.0) { category, items in
                Section(category.rawValue) {
                    ForEach(items) { item in
                        if let index = state.candidates.firstIndex(where: { $0.id == item.id }) {
                            CandidateRow(candidate: $state.candidates[index])
                        }
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Menu("选择范围") {
                Button("仅确定相关") { state.selectCertainItems() }
                Button("推荐项目") { state.selectRecommendedItems() }
            }
            Text("已选 \(state.candidates.filter(\.isSelected).count) 项 · \(ByteCountFormatter.string(fromByteCount: state.selectedSize, countStyle: .file))")
                .foregroundStyle(.secondary)
            Spacer()
            if state.isUninstalling { ProgressView().controlSize(.small) }
            Button(application.isCurrentApplication ? "卸载应用卸载器自身" : "卸载应用与所选残留", role: .destructive) {
                confirmsUninstall = true
            }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(state.isUninstalling || !state.candidates.contains(where: \.isSelected))
        }
        .padding(14)
    }
}

private struct CandidateRow: View {
    @Binding var candidate: ResidueCandidate

    var body: some View {
        Toggle(isOn: $candidate.isSelected) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.displayName).lineLimit(1)
                    Text(candidate.url?.path ?? candidate.receiptIdentifier ?? "")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(candidate.confidence.title)
                    .font(.caption).foregroundStyle(candidate.confidence == .possible ? .orange : .secondary)
                if candidate.allocatedSize > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: candidate.allocatedSize, countStyle: .file))
                        .font(.caption).monospacedDigit().frame(width: 70, alignment: .trailing)
                }
                if candidate.requiresAdministrator {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                }
            }
        }
        .help(candidate.reason)
    }
}
