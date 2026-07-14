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
        XCTAssertEqual(logger.operations.count, 1)
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
