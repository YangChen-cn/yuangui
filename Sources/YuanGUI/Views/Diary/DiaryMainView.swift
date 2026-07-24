import SwiftUI

/// 日记主视图：三栏布局
struct DiaryMainView: View {
    @ObservedObject var store: DiaryFeature
    @State private var showExport = false
    @State private var showQuickEntry = false

    var body: some View {
        HStack(spacing: 0) {
            // 左侧边栏
            DiarySidebarView(store: store)

            Divider()

            // 中间列表
            DiaryEntryList(store: store) {
                _ = store.createEntry()
            }

            Divider()

            // 右侧详情
            Group {
                switch store.viewMode {
                case .timeline:
                    if let selectedID = store.selectedEntryID,
                       let entry = store.entries.first(where: { $0.id == selectedID }) {
                        DiaryDetailEditView(store: store, entry: entry)
                    } else {
                        emptyDetail
                    }
                case .calendar:
                    DiaryCalendarView(store: store)
                case .photoWall:
                    DiaryPhotoWallView(store: store)
                case .onThisDay:
                    OnThisDayView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    _ = store.createEntry()
                } label: {
                    Image(systemName: "plus")
                }
                .help("新建日记")

                Button {
                    showQuickEntry = true
                } label: {
                    Image(systemName: "bolt")
                }
                .help("快速记录")

                Picker("视图", selection: $store.viewMode) {
                    ForEach(DiaryFeature.ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Button {
                    showExport = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("导出")
            }
        }
        .sheet(isPresented: $showExport) {
            DiaryExportView(store: store)
        }
        .sheet(isPresented: $showQuickEntry) {
            QuickDiaryEntryView(store: store) {
                // 保存后可添加桌宠反馈
            }
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("选择一篇日记或创建新日记")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Button("记录这一刻") { _ = store.createEntry() }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
