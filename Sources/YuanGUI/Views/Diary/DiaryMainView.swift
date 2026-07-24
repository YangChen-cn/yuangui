import SwiftUI

struct DiaryMainView: View {
    @ObservedObject var store: DiaryFeature
    @State private var showExport = false
    @State private var showQuickEntry = false

    var body: some View {
        NavigationSplitView {
            DiarySidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } content: {
            DiaryEntryList(store: store) { _ = store.createEntry() }
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItemGroup {
                Button { _ = store.createEntry() } label: { Image(systemName: "plus") }
                    .help("新建日记")
                Button { showQuickEntry = true } label: { Image(systemName: "bolt") }
                    .help("快速记录")
                Picker("视图", selection: $store.viewMode) {
                    ForEach(DiaryFeature.ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 390)
                saveStatus
                Button { showExport = true } label: { Image(systemName: "square.and.arrow.up") }
                    .help("导出与备份")
            }
        }
        .sheet(isPresented: $showExport) { DiaryExportView(store: store) }
        .sheet(isPresented: $showQuickEntry) { QuickDiaryEntryView(store: store) {} }
        .task { await store.loadIfNeeded() }
        .alert("操作失败", isPresented: operationErrorBinding) {
            Button("好", role: .cancel) { store.operationError = nil }
        } message: {
            Text(store.operationError ?? "未知错误")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.loadState {
        case .unloaded, .loading:
            ProgressView("正在加载手账…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("无法加载手账", systemImage: "exclamationmark.triangle", description: Text(message))
        case .loaded:
            switch store.viewMode {
            case .timeline:
                if let entry = store.selectedEntry {
                    DiaryDetailEditView(store: store, entry: entry)
                        .id(entry.id)
                } else {
                    emptyDetail
                }
            case .calendar:
                DiaryCalendarView(store: store)
            case .photoWall:
                DiaryPhotoWallView(store: store)
            case .onThisDay:
                OnThisDayView(store: store)
            case .recentlyDeleted:
                DiaryRecentlyDeletedView(store: store)
            }
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch store.saveState {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView().controlSize(.small).help("正在保存")
        case .saved:
            Image(systemName: "checkmark.circle").foregroundStyle(.green).help("已保存")
        case .failed(let message):
            Button {
                Task { _ = await store.flush() }
            } label: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }.help("保存失败，点按重试：\(message)")
        }
    }

    private var emptyDetail: some View {
        ContentUnavailableView {
            Label("选择一篇日记", systemImage: "book.closed")
        } description: {
            if !store.recoveredFiles.isEmpty {
                Text("已隔离 \(store.recoveredFiles.count) 个损坏文件，可在 Recovery 目录中恢复。")
            } else {
                Text("从列表选择日记，或记录这一刻。")
            }
        } actions: {
            Button("记录这一刻") { _ = store.createEntry() }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
        }
    }

    private var operationErrorBinding: Binding<Bool> {
        Binding(get: { store.operationError != nil }, set: { if !$0 { store.operationError = nil } })
    }
}
