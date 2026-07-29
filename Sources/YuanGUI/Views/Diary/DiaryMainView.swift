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
                store.createAndOpenEntry()
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
        .sheet(isPresented: $showQuickEntry) {
            QuickDiaryEntryView(
                store: store,
                onOpenFullDiary: { showQuickEntry = false }
            )
        }
        .task { await store.loadIfNeeded() }
        .alert(AppLocalizer.string("操作失败"), isPresented: operationErrorBinding) {
            Button(AppLocalizer.string("好"), role: .cancel) { store.operationError = nil }
        } message: {
            Text(AppLocalizer.string(store.operationError ?? "未知错误"))
        }
    }

    @ToolbarContentBuilder
    private var diaryToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { store.createAndOpenEntry() } label: {
                Image(systemName: "square.and.pencil")
            }
            .help(AppLocalizer.string("新建日记"))
            .accessibilityLabel(AppLocalizer.string("新建日记"))
            .keyboardShortcut("n", modifiers: .command)

            Button { showQuickEntry = true } label: {
                Image(systemName: "bolt")
            }
            .help(AppLocalizer.string("快速记录"))
            .accessibilityLabel(AppLocalizer.string("快速记录"))

            DiarySaveStatusView(state: store.saveState) {
                Task { _ = await store.flush() }
            }
            .font(.caption)

            Button { showExport = true } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help(AppLocalizer.string("导出与备份"))
            .accessibilityLabel(AppLocalizer.string("导出与备份"))
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.loadState {
        case .unloaded, .loading:
            ProgressView(AppLocalizer.string("正在加载手账…"))
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
                : AppLocalizer.format("diary.recoveredFiles", store.recoveredFiles.count),
            systemImage: "book.closed",
            actionTitle: "记录这一刻"
        ) {
            store.createAndOpenEntry()
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
