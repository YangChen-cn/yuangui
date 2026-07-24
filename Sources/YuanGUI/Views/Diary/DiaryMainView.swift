import SwiftUI

struct DiaryMainView: View {
    @ObservedObject var store: DiaryFeature
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var previousColumnVisibility: NavigationSplitViewVisibility = .all
    @State private var isFocusMode = false
    @State private var showExport = false
    @State private var showQuickEntry = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DiarySidebarView(store: store)
                .navigationSplitViewColumnWidth(
                    min: DiaryDesign.sidebarMinimumWidth,
                    ideal: DiaryDesign.sidebarIdealWidth,
                    max: DiaryDesign.sidebarMaximumWidth
                )
        } content: {
            DiaryEntryList(store: store) {
                store.clearFilters()
                _ = store.createEntry()
            }
                .navigationSplitViewColumnWidth(
                    min: DiaryDesign.listMinimumWidth,
                    ideal: DiaryDesign.listIdealWidth,
                    max: DiaryDesign.listMaximumWidth
                )
        } detail: {
            detail
                .navigationSplitViewColumnWidth(
                    min: DiaryDesign.editorMinimumWidth,
                    ideal: DiaryDesign.pageMaximumWidth + 48
                )
        }
        .tint(.diaryAccent)
        .toolbar { diaryToolbar }
        .sheet(isPresented: $showExport) { DiaryExportView(store: store) }
        .sheet(isPresented: $showQuickEntry) { QuickDiaryEntryView(store: store) {} }
        .task { await store.loadIfNeeded() }
        .alert("操作失败", isPresented: operationErrorBinding) {
            Button("好", role: .cancel) { store.operationError = nil }
        } message: {
            Text(store.operationError ?? "未知错误")
        }
    }

    @ToolbarContentBuilder
    private var diaryToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { _ = store.createEntry() } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("新建日记")
            .accessibilityLabel("新建日记")
            .keyboardShortcut("n", modifiers: .command)

            Button { showQuickEntry = true } label: {
                Image(systemName: "bolt")
            }
            .help("快速记录")
            .accessibilityLabel("快速记录")

            DiarySaveStatusView(state: store.saveState) {
                Task { _ = await store.flush() }
            }
            .font(.caption)

            Button { showExport = true } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("导出与备份")
            .accessibilityLabel("导出与备份")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.loadState {
        case .unloaded, .loading:
            ProgressView("正在加载手账…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            DiaryEmptyState(title: "无法加载手账", message: message, systemImage: "exclamationmark.triangle")
        case .loaded:
            loadedDetail
        }
    }

    @ViewBuilder
    private var loadedDetail: some View {
        switch store.viewMode {
        case .timeline:
            if let entry = store.selectedEntry {
                DiaryDetailEditView(
                    store: store,
                    entry: entry,
                    isFocusMode: isFocusMode,
                    onFocusModeChange: setFocusMode
                )
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

    private var emptyDetail: some View {
        DiaryEmptyState(
            title: "选择一篇日记",
            message: store.recoveredFiles.isEmpty
                ? "从时间线选择一篇日记，或记录这一刻。"
                : "已隔离 \(store.recoveredFiles.count) 个损坏文件，可在 Recovery 目录中恢复。",
            systemImage: "book.closed",
            actionTitle: "记录这一刻"
        ) {
            _ = store.createEntry()
        }
    }

    private var operationErrorBinding: Binding<Bool> {
        Binding(
            get: { store.operationError != nil },
            set: { if !$0 { store.operationError = nil } }
        )
    }

    private func setFocusMode(_ enabled: Bool) {
        if enabled {
            previousColumnVisibility = columnVisibility
            columnVisibility = .detailOnly
        } else {
            columnVisibility = previousColumnVisibility
        }
        isFocusMode = enabled
    }
}
