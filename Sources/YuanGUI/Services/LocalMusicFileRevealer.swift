import AppKit
import Foundation

@MainActor
protocol LocalMusicFileRevealing: AnyObject {
    func reveal(_ url: URL)
}

@MainActor
final class WorkspaceLocalMusicFileRevealer: LocalMusicFileRevealing {
    static let shared = WorkspaceLocalMusicFileRevealer()

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
