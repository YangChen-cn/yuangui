import AppKit
import SwiftUI

struct ScreenshotEditorToolbar: View {
    @ObservedObject var store: ScreenshotEditorStore
    @State private var showsKeys = false
    @State private var showsWidth = false
    private let groups: [[ScreenshotTool]] = [[.select, .pen, .highlighter], [.line, .arrow, .rectangle, .ellipse], [.text, .marker], [.mosaic, .blur]]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(badges: true)
            row(badges: false)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .onDisappear { store.endStyleEditing() }
    }

    private func row(badges: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(groups.indices, id: \.self) { index in
                if index > 0 { separator }
                HStack(spacing: 2) {
                    ForEach(groups[index]) { tool in
                        Button { store.endStyleEditing(); store.selectedTool = tool } label: {
                            VStack(spacing: 0) {
                                Group {
                                    if tool == .text { Text("T").font(.system(size: 17, weight: .medium, design: .serif)) }
                                    else { Image(systemName: tool.systemImage).font(.system(size: 16)) }
                                }.frame(height: 21)
                                if badges { Text(tool.shortcut.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary) }
                            }.frame(width: badges ? 32 : 27, height: 36)
                        }
                        .buttonStyle(ScreenshotToolButtonStyle(selected: store.selectedTool == tool))
                        .help("\(tool.title) · \(tool.shortcut.uppercased())")
                        .accessibilityLabel("\(tool.title) · \(tool.shortcut.uppercased())")
                        .accessibilityAddTraits(store.selectedTool == tool ? .isSelected : [])
                    }
                }
            }
            separator
            ScreenshotColorSwatch(store: store).frame(width: 24, height: 24)
            Button { showsWidth.toggle() } label: {
                Text("\(Int(store.usesFontSize ? store.fontSize : store.lineWidth)) px")
                    .monospacedDigit().font(.caption).frame(width: 48, height: 32)
            }.buttonStyle(ScreenshotToolButtonStyle())
                .disabled(!store.canEditStyle)
                .help(sizeTitle)
                .popover(isPresented: $showsWidth) {
                    VStack(alignment: .leading) {
                        Text(sizeTitle).font(.headline)
                        Slider(value: Binding(get: { store.usesFontSize ? store.fontSize : store.lineWidth }, set: {
                            if store.usesFontSize { store.fontSize = $0 } else { store.lineWidth = $0 }
                        }), in: store.usesFontSize ? 10...96 : 2...24, step: 1, onEditingChanged: {
                            if $0 { store.beginStyleEditing() } else { store.endStyleEditing() }
                        })
                        Text("\(Int(store.usesFontSize ? store.fontSize : store.lineWidth)) px").monospacedDigit()
                    }.padding(16).frame(width: 220).onDisappear { store.endStyleEditing() }
                }
            separator
            action("arrow.uturn.backward", "capture.undoShortcut", enabled: store.canUndo) { store.undo() }
            action("arrow.uturn.forward", "capture.redoShortcut", enabled: store.canRedo) { store.redo() }
            action("trash", "capture.deleteSelected", enabled: store.selectedAnnotationID != nil) { store.deleteSelected() }
            Menu {
                Button(AppLocalizer.string("清除全部标注"), role: .destructive) { store.clear() }
            } label: { Image(systemName: "ellipsis").frame(width: 20) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .help(AppLocalizer.string("清除全部标注"))
            Button { showsKeys.toggle() } label: { Image(systemName: "keyboard").frame(width: 28, height: 32) }
                .buttonStyle(ScreenshotToolButtonStyle()).help(AppLocalizer.string("capture.shortcuts"))
                .accessibilityLabel(AppLocalizer.string("capture.shortcuts"))
                .popover(isPresented: $showsKeys) { shortcutHelp }
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var separator: some View { Divider().frame(height: 24) }
    private var sizeTitle: String {
        AppLocalizer.string(store.styleTool == .text ? "capture.fontSize" : store.styleTool == .marker ? "capture.markerSize" : store.styleTool == .mosaic ? "capture.brushSize" : "capture.strokeWidth")
    }
    private func action(_ icon: String, _ title: String, enabled: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Image(systemName: icon).frame(width: 26, height: 32) }
            .buttonStyle(ScreenshotToolButtonStyle()).disabled(!enabled)
            .help(AppLocalizer.string(title)).accessibilityLabel(AppLocalizer.string(title))
    }
    private var shortcutHelp: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalizer.string("capture.shortcuts")).font(.headline)
                Text(AppLocalizer.string("工具")).font(.subheadline.bold())
                ForEach(groups.flatMap { $0 }) { tool in helpRow(tool.shortcut.uppercased(), tool.title) }
                Divider()
                Text(AppLocalizer.string("capture.edit")).font(.subheadline.bold())
                helpRow("⌘Z / ⇧⌘Z", AppLocalizer.string("capture.undoRedo"))
                helpRow("Delete", AppLocalizer.string("capture.deleteSelected"))
                helpRow("[ / ] · ⌥ Scroll", AppLocalizer.string("capture.adjustSize"))
                helpRow("⌘C / ⌘S", AppLocalizer.string("capture.copySave"))
                helpRow("⇧⌘C", AppLocalizer.string("复制并保存"))
                Divider()
                helpRow("Shift", AppLocalizer.string("capture.constrain"))
                helpRow("⌘Enter / Esc", AppLocalizer.string("capture.textCommitCancel"))
                helpRow("Pinch · ⌘ Scroll", AppLocalizer.string("capture.zoom"))
                helpRow("Space + Drag", AppLocalizer.string("capture.pan"))
                helpRow("0 / 1", AppLocalizer.string("capture.fitActual"))
            }.padding(16)
        }.frame(width: 350, height: 530)
    }
    private func helpRow(_ key: String, _ title: String) -> some View {
        HStack { Text(key).font(.system(.caption, design: .monospaced)).frame(width: 124, alignment: .leading); Text(title).font(.caption); Spacer(minLength: 0) }
    }
}

private struct ScreenshotToolButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        ScreenshotToolButtonSurface(content: configuration.label, selected: selected, pressed: configuration.isPressed)
    }
}
private struct ScreenshotToolButtonSurface<Content: View>: View {
    let content: Content
    let selected: Bool
    let pressed: Bool
    @State private var hover = false
    var body: some View {
        content.foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(hover ? 0.065 : 0), in: .rect(cornerRadius: 5))
            .opacity(pressed ? 0.65 : 1).contentShape(.rect).onHover { hover = $0 }
    }
}
