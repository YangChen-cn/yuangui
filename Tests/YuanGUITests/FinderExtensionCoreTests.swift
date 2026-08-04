import Foundation
import XCTest
@testable import YuanGUIFinderCore

final class FinderExtensionCoreTests: XCTestCase {
    func testTargetResolutionDistinguishesContainerFilesAndFolders() throws {
        try withTemporaryDirectory { root in
            let folder = root.appendingPathComponent("Folder", isDirectory: true)
            let file = root.appendingPathComponent("note.txt")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data().write(to: file)

            XCTAssertEqual(
                FinderTargetResolver.creationDirectory(target: root, kind: .container),
                root.resolvingSymlinksInPath()
            )
            XCTAssertEqual(
                FinderTargetResolver.creationDirectory(target: folder, kind: .items),
                root.resolvingSymlinksInPath()
            )
            XCTAssertEqual(
                FinderTargetResolver.terminalDirectory(target: folder, kind: .items),
                folder.resolvingSymlinksInPath()
            )
            XCTAssertEqual(
                FinderTargetResolver.terminalDirectory(target: file, kind: .items),
                root.resolvingSymlinksInPath()
            )
            XCTAssertEqual(
                FinderTargetResolver.terminalDirectory(
                    target: root,
                    selected: [folder],
                    kind: .items
                ),
                folder.resolvingSymlinksInPath()
            )
            XCTAssertEqual(
                FinderTargetResolver.terminalDirectory(
                    target: folder,
                    selected: [file],
                    kind: .items
                ),
                root.resolvingSymlinksInPath()
            )
            XCTAssertEqual(
                FinderTargetResolver.pasteDirectory(target: folder, kind: .items),
                folder.resolvingSymlinksInPath()
            )
            XCTAssertNil(FinderTargetResolver.pasteDirectory(target: file, kind: .items))
        }
    }

    func testDesktopDirectoryDetectionUsesCanonicalSystemURL() throws {
        try withTemporaryDirectory { root in
            let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
            let other = root.appendingPathComponent("Documents", isDirectory: true)
            try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

            XCTAssertTrue(FinderTargetResolver.isDesktopDirectory(
                desktop,
                desktopDirectories: [desktop]
            ))
            XCTAssertFalse(FinderTargetResolver.isDesktopDirectory(
                other,
                desktopDirectories: [desktop]
            ))
        }
    }

    func testFileCreatorCreatesEveryTemplateAndUsesUniqueNamesWithoutOverwriting() throws {
        try withTemporaryDirectory { root in
            for template in FinderFileTemplate.allCases {
                let created = try FinderFileCreator.create(
                    template: template,
                    baseName: "Template-\(template.rawValue)",
                    in: root
                )
                XCTAssertEqual(created.pathExtension, template.pathExtension)
                XCTAssertEqual(try Data(contentsOf: created), template.data)
            }

            let first = try FinderFileCreator.create(
                template: .text,
                baseName: "New Text Document",
                in: root
            )
            try Data("keep".utf8).write(to: first)
            let second = try FinderFileCreator.create(
                template: .text,
                baseName: "New Text Document",
                in: root
            )

            XCTAssertEqual(first.lastPathComponent, "New Text Document.txt")
            XCTAssertEqual(second.lastPathComponent, "New Text Document 2.txt")
            XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "keep")
        }
    }

    func testAllTemplatesHaveExpectedExtensionsAndReadableOfficePackages() throws {
        XCTAssertEqual(
            FinderFileTemplate.allCases.map(\.pathExtension),
            ["txt", "md", "docx", "xlsx", "pptx"]
        )
        XCTAssertTrue(FinderFileTemplate.text.data.isEmpty)
        XCTAssertTrue(FinderFileTemplate.markdown.data.isEmpty)
        try assertPackage(.word, contains: ["[Content_Types].xml", "_rels/.rels", "word/document.xml"])
        try assertPackage(.excel, contains: [
            "[Content_Types].xml",
            "_rels/.rels",
            "xl/workbook.xml",
            "xl/_rels/workbook.xml.rels",
            "xl/worksheets/sheet1.xml"
        ])
        try assertPackage(.powerpoint, contains: [
            "[Content_Types].xml",
            "_rels/.rels",
            "ppt/presentation.xml",
            "ppt/_rels/presentation.xml.rels",
            "ppt/slideMasters/slideMaster1.xml",
            "ppt/slideLayouts/slideLayout1.xml",
            "ppt/slides/slide1.xml"
        ])
    }

    func testClipboardPathFormattingUsesOnePathPerLine() throws {
        try withTemporaryDirectory { root in
            let first = root.appendingPathComponent("one.txt")
            let second = root.appendingPathComponent("two.md")

            XCTAssertEqual(FinderClipboardFormatter.pathString(for: [first]), first.path)
            XCTAssertEqual(
                FinderClipboardFormatter.pathString(for: [first, second]),
                "\(first.path)\n\(second.path)"
            )
            XCTAssertNil(FinderClipboardFormatter.pathString(for: []))
        }
    }

    func testCutPayloadRoundTripsWithIdentity() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("source.txt")
            try Data("source".utf8).write(to: source)
            let item = try FinderCutItem.capture(source)
            let payload = FinderCutPayload(items: [item])
            let encoded = try FinderCutPayloadCodec.encode(payload)

            XCTAssertEqual(FinderCutPayloadCodec.decode(encoded), payload)
            XCTAssertNil(FinderCutPayloadCodec.decode(Data("clipboard replaced".utf8)))
            XCTAssertNil(FinderCutPayloadCodec.decode(nil))
            XCTAssertEqual(item.path, source.resolvingSymlinksInPath().path)
        }
    }

    func testMoveRevalidatesIdentityAndKeepsChangedSource() throws {
        try withTemporaryDirectory { root in
            let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
            let destination = root.appendingPathComponent("Destination", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let source = sourceDirectory.appendingPathComponent("item.txt")
            try Data("before".utf8).write(to: source)
            let captured = try FinderCutItem.capture(source)
            try FileManager.default.removeItem(at: source)
            try Data("after".utf8).write(to: source)

            let result = FinderMoveService.move(FinderCutPayload(items: [captured]), to: destination)

            XCTAssertTrue(result.movedURLs.isEmpty)
            XCTAssertEqual(result.failures.map(\.reason), [.sourceChanged])
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        }
    }

    func testMoveNeverOverwritesAndRetainsOnlyFailedItems() throws {
        try withTemporaryDirectory { root in
            let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
            let destination = root.appendingPathComponent("Destination", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let movable = sourceDirectory.appendingPathComponent("move.txt")
            let conflicting = sourceDirectory.appendingPathComponent("keep.txt")
            try Data("move".utf8).write(to: movable)
            try Data("source".utf8).write(to: conflicting)
            try Data("destination".utf8).write(to: destination.appendingPathComponent("keep.txt"))
            let items = try [movable, conflicting].map { try FinderCutItem.capture($0) }

            let result = FinderMoveService.move(FinderCutPayload(items: items), to: destination)

            XCTAssertEqual(result.movedURLs.map(\.lastPathComponent), ["move.txt"])
            XCTAssertEqual(result.failures.map(\.reason), [.destinationExists])
            XCTAssertEqual(result.remainingItems, [items[1]])
            XCTAssertEqual(
                try String(contentsOf: destination.appendingPathComponent("keep.txt"), encoding: .utf8),
                "destination"
            )
        }
    }

    func testMoveRejectsSameDirectoryAndDirectoryDescendant() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("Folder", isDirectory: true)
            let child = source.appendingPathComponent("Child", isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            let item = try FinderCutItem.capture(source)

            let sameDirectory = FinderMoveService.move(FinderCutPayload(items: [item]), to: root)
            let descendant = FinderMoveService.move(FinderCutPayload(items: [item]), to: child)

            XCTAssertEqual(sameDirectory.failures.map(\.reason), [.sameDirectory])
            XCTAssertEqual(descendant.failures.map(\.reason), [.destinationInsideSource])
        }
    }

    private func assertPackage(_ template: FinderFileTemplate, contains names: [String]) throws {
        let data = template.data
        XCTAssertEqual(Array(data.prefix(2)), Array("PK".utf8))
        try withTemporaryDirectory { root in
            let package = root.appendingPathComponent("template.\(template.pathExtension)")
            try data.write(to: package)
            let listed = try runUnzip(arguments: ["-Z1", package.path])
            let entries = Set(listed.split(separator: "\n").map(String.init))
            XCTAssertTrue(Set(names).isSubset(of: entries), "Missing OOXML entries")
            _ = try runUnzip(arguments: ["-tqq", package.path])
        }
    }

    private func runUnzip(arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let string = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, string)
        return string
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YuanGUI-FinderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
