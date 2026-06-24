import SwiftUI

struct OrphanScanView: View {
    @EnvironmentObject private var state: AppState

    private var grouped: [(ResidueCategory, [ResidueCandidate])] {
        Dictionary(grouping: state.orphanCandidates, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.0.rawValue < $1.0.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            actionBar
        }
        .frame(minWidth: 640, minHeight: 460)
        .task { if state.orphanCandidates.isEmpty { await state.scanOrphans() } }
    }

    @ViewBuilder private var content: some View {
        if state.isScanningOrphans {
            Spacer()
            ProgressView("正在扫描孤儿残留…")
            Spacer()
        } else if state.orphanCandidates.isEmpty {
            Spacer()
            ContentUnavailableView(
                "未发现孤儿残留",
                systemImage: "sparkles",
                description: Text("已检查启动项、应用数据、缓存、配置与安装收据，未发现所属应用已移除的残留")
            )
            Button("重新扫描") { Task { await state.scanOrphans() } }
                .buttonStyle(.borderedProminent)
            Spacer()
        } else {
            List {
                ForEach(grouped, id: \.0) { category, items in
                    Section(category.rawValue) {
                        ForEach(items) { item in
                            if let index = state.orphanCandidates.firstIndex(where: { $0.id == item.id }) {
                                OrphanRow(candidate: $state.orphanCandidates[index])
                            }
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("孤儿残留扫描").font(.title2).fontWeight(.semibold)
                Text("这些项目位于残留目录中，但未匹配到任何已安装应用。仅清理你确认无用的项目。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("重新扫描") { Task { await state.scanOrphans() } }
                .disabled(state.isScanningOrphans || state.isUninstalling)
        }
        .padding(20)
    }

    private var actionBar: some View {
        HStack {
            Menu("选择范围") {
                Button("推荐项目") { state.selectRecommendedOrphans() }
            }
            Text("已选 \(state.orphanCandidates.filter(\.isSelected).count) 项 · \(ByteCountFormatter.string(fromByteCount: state.selectedOrphanSize, countStyle: .file))")
                .foregroundStyle(.secondary)
            Spacer()
            if state.isUninstalling { ProgressView().controlSize(.small) }
            Button("清理所选残留", role: .destructive) {
                Task { await state.cleanupSelectedOrphans() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(state.isUninstalling || !state.orphanCandidates.contains(where: \.isSelected))
        }
        .padding(14)
    }
}

private struct OrphanRow: View {
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
                    .font(.caption)
                    .foregroundStyle(candidate.confidence == .possible ? .orange : .secondary)
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
