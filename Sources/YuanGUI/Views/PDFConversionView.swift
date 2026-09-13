import SwiftUI
import AppKit

struct PDFConversionView: View {
    @ObservedObject var store: PDFConversionStore
    let chooseFile: () -> Void
    let chooseDestination: () -> Void
    @State private var dropTargeted = false
    @State private var confirmingUninstall = false

    private static let byteCount = ByteCountFormatter()

    private var stageKey: String {
        store.stage == "text" && store.ocrApplied ? "pdf.stage.textOCR" : "pdf.stage.\(store.stage)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.richtext").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLocalizer.string("pdf.title")).font(.title2.bold())
                    Text(AppLocalizer.string("pdf.subtitle")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(AppLocalizer.string("pdf.choose"), action: chooseFile)
                    .keyboardShortcut("o", modifiers: .command).disabled(store.isBusy)
            }
            HStack {
                Label(store.source?.lastPathComponent ?? AppLocalizer.string("pdf.drop"), systemImage: "doc.fill")
                    .lineLimit(2).textSelection(.enabled)
                if let probe = store.probe, !probe.encrypted, probe.pages > 0 {
                    Text(AppLocalizer.format("pdf.pageCount", probe.pages)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isBusy {
                    ProgressView().controlSize(.small)
                    Button(AppLocalizer.string("pdf.cancel"), action: store.cancel)
                        .keyboardShortcut(.cancelAction)
                } else if store.isReady {
                    Button(AppLocalizer.string("pdf.convert"), action: store.convert)
                        .buttonStyle(.borderedProminent).disabled(store.source == nil)
                        .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button(AppLocalizer.string("pdf.install"), action: store.install).buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .background(dropTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .dropDestination(for: URL.self) { urls, _ in
                guard !store.isBusy else { return false }
                store.select(urls)
                return urls.count == 1 && urls.first?.pathExtension.lowercased() == "pdf"
            } isTargeted: { dropTargeted = $0 }
            if !store.isReady {
                Text(AppLocalizer.string("pdf.installHelp")).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(get: { store.ocrEnabled }, set: store.setOCR)) {
                    Text(AppLocalizer.string("pdf.ocr")).font(.callout)
                }
                .toggleStyle(.checkbox)
                .disabled(store.isBusy)
                Text(AppLocalizer.string("pdf.ocrHelp")).font(.caption).foregroundStyle(.secondary)
                if store.probe?.scanned == true {
                    Text(AppLocalizer.string(store.ocrEnabled ? "pdf.scanned" : "pdf.scannedNoOCR"))
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle(isOn: Binding(get: { store.removeHeaderFooter }, set: store.setRemoveHeaderFooter)) {
                    Text(AppLocalizer.string("pdf.margins")).font(.callout)
                }
                .toggleStyle(.checkbox)
                .disabled(store.isBusy)
                Text(AppLocalizer.string("pdf.marginsHelp")).font(.caption).foregroundStyle(.secondary)
            }
            if store.isReady, store.runtimeBytes > 0 {
                HStack {
                    Text(AppLocalizer.format("pdf.runtimeSize", Self.byteCount.string(fromByteCount: store.runtimeBytes)))
                    Button(AppLocalizer.string("pdf.uninstall")) { confirmingUninstall = true }
                        .disabled(store.isBusy)
                    Spacer()
                }.font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(AppLocalizer.string(stageKey))
                Spacer()
                if let started = store.startedAt {
                    PDFElapsedView(started: started)
                } else if store.elapsed > 0 {
                    Text(AppLocalizer.format("pdf.elapsed", store.elapsed)).monospacedDigit()
                }
            }.font(.caption).foregroundStyle(.secondary)
            if let error = store.error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).lineLimit(5)
            }
            if let result = store.result {
                if result.manifest.emptyText {
                    Text(AppLocalizer.string(store.ocrApplied ? "pdf.emptyText" : "pdf.emptyTextNoOCR"))
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Text(AppLocalizer.format("pdf.imageCount", result.manifest.images.count))
                    if result.truncated { Text(AppLocalizer.string("pdf.truncated")) }
                }.font(.caption).foregroundStyle(.secondary)
                if !result.manifest.images.isEmpty {
                    Text(AppLocalizer.string("pdf.imageAssets")).font(.caption).foregroundStyle(.secondary)
                }
                PDFSourceTextView(text: result.preview)
                HStack {
                    Button(AppLocalizer.string("pdf.copy"), action: store.copy)
                    Button(AppLocalizer.string("pdf.export"), action: chooseDestination)
                        .keyboardShortcut("s", modifiers: .command)
                    if let url = store.exportedURL {
                        Button(AppLocalizer.string("pdf.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Spacer()
                }.disabled(store.isBusy)
            } else {
                ContentUnavailableView(AppLocalizer.string("pdf.emptyTitle"), systemImage: "doc.text.magnifyingglass",
                    description: Text(AppLocalizer.string("pdf.limitations")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(minWidth: 580, minHeight: 420)
        .confirmationDialog(AppLocalizer.string("pdf.uninstall.confirm"), isPresented: $confirmingUninstall,
                            titleVisibility: .visible) {
            Button(AppLocalizer.string("pdf.uninstall"), role: .destructive) { store.uninstall() }
            Button(AppLocalizer.string("pdf.cancel"), role: .cancel) { }
        } message: {
            Text(AppLocalizer.string("pdf.uninstall.detail"))
        }
    }
}

/// Only this small label ticks; the document preview is not refreshed by a timer.
private struct PDFElapsedView: View {
    let started: Date
    var body: some View {
        TimelineView(.periodic(from: started, by: 1)) { context in
            Text(AppLocalizer.format("pdf.elapsed", max(0, context.date.timeIntervalSince(started))))
                .monospacedDigit()
        }
    }
}

private struct PDFSourceTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.textContainerInset = NSSize(width: 10, height: 10)
        view.setAccessibilityLabel(AppLocalizer.string("pdf.source"))
        scroll.borderType = .bezelBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
        view.scrollToBeginningOfDocument(nil)
    }
}
