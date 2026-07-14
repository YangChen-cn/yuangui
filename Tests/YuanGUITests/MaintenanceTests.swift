import Foundation
import XCTest
@testable import YuanGUI

final class MaintenanceTests: XCTestCase {
    func testSafePathValidatorAcceptsChildAndRejectsRootTraversalAndSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SafePathTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("cache")
        try Data("x".utf8).write(to: child)
        let validator = SafePathValidator(allowedRoots: [root])

        XCTAssertEqual(try validator.validate(child).path, child.path)
        XCTAssertThrowsError(try validator.validate(root))
        XCTAssertThrowsError(try validator.validate(URL(fileURLWithPath: "/System/Library")))

        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: child)
        XCTAssertThrowsError(try validator.validate(link))
    }

    func testCleanupPermanentlyRemovesOnlyValidatedCandidate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CleanupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("cache.bin")
        try Data(repeating: 1, count: 20).write(to: file)
        let logger = MemoryMaintenanceLogger()
        let service = NativeMaintenanceService(
            validator: SafePathValidator(allowedRoots: [root]),
            logger: logger
        )
        let candidate = CleanupCandidate(
            url: file, displayName: "cache.bin", category: .appCache,
            disposition: .permanent, byteCount: 20, modifiedAt: nil
        )

        let result = await service.clean([candidate])

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(result.itemCount, 1)
        XCTAssertEqual(result.reclaimedBytes, 20)
        XCTAssertEqual(result.permanentlyDeletedBytes, 20)
        XCTAssertEqual(result.trashedBytes, 0)
        XCTAssertEqual(result.results?.first?.outcome, .deleted)
        XCTAssertEqual(logger.operations.count, 1)
    }

    func testCleanupSkipsCandidateChangedAfterScan() async throws {
        let root = temporaryRoot("CleanupChanged")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("cache.bin")
        try Data(repeating: 1, count: 20).write(to: file)
        let candidate = CleanupCandidate(
            url: file, displayName: "cache.bin", category: .appCache,
            disposition: .permanent, byteCount: 20, modifiedAt: nil
        )
        try Data(repeating: 2, count: 40).write(to: file)
        let service = NativeMaintenanceService(
            validator: SafePathValidator(allowedRoots: [root]),
            logger: MemoryMaintenanceLogger()
        )

        let result = await service.clean([candidate])

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(result.itemCount, 0)
        XCTAssertEqual(result.results?.first?.outcome, .skipped)
        XCTAssertFalse(result.skipped.isEmpty)
    }

    func testValidatorRejectsControlCharactersProtectedAndRootPaths() throws {
        let root = temporaryRoot("Validator")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let validator = SafePathValidator(allowedRoots: [root])

        XCTAssertThrowsError(try validator.validate(root))
        XCTAssertThrowsError(try validator.validate(root.appendingPathComponent("bad\nname")))
        XCTAssertThrowsError(try validator.validate(root.appendingPathComponent("Group Containers/shared")))
        XCTAssertThrowsError(try validator.validate(URL(fileURLWithPath: "/")))
        XCTAssertTrue(BundleIdentifierValidator.isValid("com.example.good-helper"))
        XCTAssertFalse(BundleIdentifierValidator.isValid("com..example"))
        XCTAssertFalse(BundleIdentifierValidator.isValid("example"))
    }

    func testRuleScanUsesConservativeDefaultsInTemporaryTree() async throws {
        let root = temporaryRoot("RuleScan")
        let library = root.appendingPathComponent("Library")
        let apps = root.appendingPathComponent("Applications")
        let temp = root.appendingPathComponent("Temporary")
        let cache = library.appendingPathComponent("Caches/com.example.rebuildable")
        let browser = library.appendingPathComponent("Caches/Google")
        let orphan = library.appendingPathComponent("Application Support/com.example.orphan")
        for directory in [cache, browser, orphan, apps, temp] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 8_192).write(to: directory.appendingPathComponent("data"))
        }
        let old = Date(timeIntervalSinceNow: -40 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: orphan.path)
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = CleanupScanner(
            userLibrary: library,
            temporaryDirectory: temp,
            applicationRoots: [(apps, .userApplications)],
            metadataCacheRoot: root.appendingPathComponent("Metadata")
        )

        let values = await scanner.scan(excluding: [])

        let normal = try XCTUnwrap(
            values.first { $0.url.standardizedFileURL.path == cache.standardizedFileURL.path },
            "扫描结果：\(values.map { $0.url.path })"
        )
        XCTAssertEqual(normal.risk, .recommended)
        XCTAssertTrue(normal.selectedByDefault)
        let browserValue = try XCTUnwrap(values.first {
            $0.url.standardizedFileURL.path == browser.standardizedFileURL.path
        })
        XCTAssertEqual(browserValue.category, .browserCache)
        XCTAssertFalse(browserValue.selectedByDefault)
        let orphanValue = try XCTUnwrap(values.first {
            $0.url.standardizedFileURL.path == orphan.standardizedFileURL.path
        })
        XCTAssertEqual(orphanValue.risk, .review)
        XCTAssertEqual(orphanValue.disposition, .recycle)
        XCTAssertFalse(orphanValue.selectedByDefault)
    }

    func testSameBundleIDSiblingsPreserveAllSharedState() async throws {
        let root = temporaryRoot("SiblingGuard")
        let apps = root.appendingPathComponent("Applications")
        let library = root.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let bundleID = "com.example.sibling.\(UUID().uuidString.lowercased())"
        try makeApplication(at: apps.appendingPathComponent("One.app"), bundleID: bundleID, name: "One")
        try makeApplication(at: apps.appendingPathComponent("Two.app"), bundleID: bundleID, name: "Two")
        let residual = library.appendingPathComponent("Caches/\(bundleID)")
        try FileManager.default.createDirectory(at: residual, withIntermediateDirectories: true)
        try Data([1]).write(to: residual.appendingPathComponent("data"))
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = CleanupScanner(
            userLibrary: library,
            applicationRoots: [(apps, .userApplications)],
            metadataCacheRoot: root.appendingPathComponent("Metadata")
        )

        let applications = await scanner.scanApplications()

        XCTAssertEqual(applications.count, 2)
        XCTAssertTrue(applications.allSatisfy { $0.components.count == 1 })
        XCTAssertTrue(applications.allSatisfy { $0.warnings.contains { $0.contains("相同 Bundle ID") } })
    }

    func testEmbeddedHelperBundleIDFindsExactResidual() async throws {
        let root = temporaryRoot("EmbeddedHelper")
        let apps = root.appendingPathComponent("Applications")
        let library = root.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let app = apps.appendingPathComponent("Host.app")
        try makeApplication(at: app, bundleID: "com.example.host.\(UUID().uuidString.lowercased())", name: "Host")
        let helperID = "com.example.helper.\(UUID().uuidString.lowercased())"
        try makeApplication(
            at: app.appendingPathComponent("Contents/Library/LoginItems/Helper.app"),
            bundleID: helperID,
            name: "Helper"
        )
        let residual = library.appendingPathComponent("Caches/\(helperID)")
        try FileManager.default.createDirectory(at: residual, withIntermediateDirectories: true)
        try Data([1]).write(to: residual.appendingPathComponent("data"))
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = CleanupScanner(
            userLibrary: library,
            applicationRoots: [(apps, .userApplications)],
            metadataCacheRoot: root.appendingPathComponent("Metadata")
        )

        XCTAssertTrue(scanner.embeddedBundleIdentifiers(in: app).contains(helperID))

        let scannedApplications = await scanner.scanApplications()
        let application = try XCTUnwrap(scannedApplications.first)

        XCTAssertTrue(application.components.contains {
            $0.url.standardizedFileURL.path == residual.standardizedFileURL.path && $0.confidence == .exact
        })
    }

    func testSensitiveAndBrowserCachesAreNotDefaultCleanup() {
        let scanner = CleanupScanner()
        XCTAssertTrue(scanner.isBrowserCache(URL(fileURLWithPath: "/tmp/Google")))
        XCTAssertTrue(scanner.isBrowserCache(URL(fileURLWithPath: "/tmp/com.microsoft.Edge")))
        XCTAssertTrue(scanner.isProtectedCache(URL(fileURLWithPath: "/tmp/com.apple.securityd")))
        XCTAssertTrue(scanner.isProtectedCache(URL(fileURLWithPath: "/tmp/com.microsoft.VSCode")))
        XCTAssertFalse(CleanupCategory.browserCache.selectedByDefault)
        XCTAssertFalse(CleanupCategory.temporary.selectedByDefault)
    }

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeApplication(at url: URL, bundleID: String, name: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    @MainActor
    func testLoginItemStoreMapsRequiresApprovalAndFailure() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let store = LoginItemStore(service: service)
        XCTAssertTrue(store.isEnabled)
        store.setEnabled(false)
        XCTAssertEqual(store.status, .disabled)
    }
}

private final class MemoryMaintenanceLogger: MaintenanceLogging {
    var operations: [MaintenanceOperation] = []
    func load() -> [MaintenanceOperation] { operations }
    func append(_ operation: MaintenanceOperation) throws { operations.insert(operation, at: 0) }
}

private final class FakeLoginItemService: LoginItemManaging {
    var status: LoginItemStatus
    init(status: LoginItemStatus) { self.status = status }
    func setEnabled(_ enabled: Bool) throws { status = enabled ? .enabled : .disabled }
    func openSystemSettings() {}
}
