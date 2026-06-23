import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("应用卸载器", systemImage: "trash.square.fill")
                        .font(.title2.weight(.semibold))
                    Text("选择应用，扫描并清理卸载残留")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()

                Group {
                    if state.isLoadingApplications && state.applications.isEmpty {
                        ProgressView("正在读取应用…")
                    } else {
                        List(state.filteredApplications, selection: $state.selection) { application in
                            ApplicationRow(application: application)
                                .tag(application.id)
                        }
                        .searchable(text: $state.searchText, prompt: "搜索要卸载的应用")
                    }
                }
            }
            .navigationTitle("应用卸载器")
            .toolbar {
                Button { state.showsHistory = true } label: {
                    Label("卸载记录", systemImage: "clock.arrow.circlepath")
                }
            }
        } detail: {
            if let application = state.selectedApplication {
                ApplicationDetailView(application: application)
                    .id(application.id)
            } else {
                ContentUnavailableView(
                    "选择要卸载的应用",
                    systemImage: "trash.square",
                    description: Text("将扫描应用本体、缓存、配置和后台组件")
                )
            }
        }
        .onChange(of: state.selection) {
            state.candidates = []
        }
        .sheet(isPresented: $state.showsHistory) {
            HistoryView()
                .environmentObject(state)
        }
        .alert("操作失败", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) { Button("好") {} } message: { Text(state.errorMessage ?? "") }
        .alert("完成", isPresented: Binding(
            get: { state.completionMessage != nil },
            set: { if !$0 { state.completionMessage = nil } }
        )) { Button("好") {} } message: { Text(state.completionMessage ?? "") }
    }
}

private struct ApplicationRow: View {
    let application: InstalledApplication

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(application.name).lineLimit(1)
                Text(application.version ?? application.bundleIdentifier ?? "未知版本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
