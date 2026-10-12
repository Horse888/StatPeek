import AppKit
import XCTest

final class CompactLayoutAndLoginTests: XCTestCase {
    func testFourMetricsUseLessThan115PointsAndDoNotJumpAtFullLoad() {
        let rows = StatusLayout.rows(for: Set(Metric.allCases))
        let idle = StatusStripLayout(rows: rows, readings: [.disk: "0.0B", .cpu: "0.0%", .memory: "0.0%", .gpu: "不可用"])
        let full = StatusStripLayout(rows: rows, readings: [.disk: "999.9M", .cpu: "100.0%", .memory: "100.0%", .gpu: "100.0%"])
        XCTAssertLessThan(full.width, 115)
        XCTAssertEqual(idle.width, full.width)
        XCTAssertEqual(idle.columnWidths, full.columnWidths)
    }

    func testAllSelectionsFitWorstCaseReadingsWithoutClippingOrOverlapping() {
        let readings: [Metric: String] = [.disk: "999.9M", .cpu: "100.0%", .memory: "100.0%", .gpu: "100.0%"]
        for bits in 0..<16 {
            let selected = Set(Metric.allCases.enumerated().filter { bits & (1 << $0.offset) != 0 }.map(\.element))
            let rows = StatusLayout.rows(for: selected)
            let layout = StatusStripLayout(rows: rows, readings: readings)
            for row in rows {
                for (column, metric) in row.enumerated() {
                    let rightEdge = layout.origin(of: column) + StatusStripLayout.iconWidth + StatusStripLayout.iconGap
                        + StatusStripLayout.textWidth(metric.compact(readings[metric]))
                    XCTAssertLessThanOrEqual(rightEdge, layout.width - StatusStripLayout.sidePadding)
                    if column + 1 < row.count {
                        XCTAssertLessThan(rightEdge, layout.origin(of: column + 1))
                    }
                }
            }
            if selected.isEmpty { XCTAssertGreaterThanOrEqual(layout.width, 22) }
        }
    }

    @MainActor
    func testLoginItemDoesNotRegisterOnLaunchAndReflectsExternalChanges() {
        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service)
        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertEqual(service.registerCalls, 0)
        service.status = .enabled
        XCTAssertEqual(controller.status, .enabled)
        service.status = .requiresApproval
        XCTAssertEqual(controller.status, .requiresApproval)
    }

    @MainActor
    func testLoginRegistrationAndUnregistrationSurviveControllerRelaunch() {
        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertEqual(LoginItemController(service: service).status, .enabled)
        controller.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 1)
        controller.setEnabled(false)
        XCTAssertEqual(LoginItemController(service: service).status, .notRegistered)
        controller.setEnabled(false)
        XCTAssertEqual(service.unregisterCalls, 1)
    }

    @MainActor
    func testPendingApprovalIsReportedAndCanBeCancelled() {
        let service = FakeLoginItemService()
        service.registrationStatus = .requiresApproval
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertEqual(controller.status, .requiresApproval)
        controller.setEnabled(false)
        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertEqual(service.unregisterCalls, 1)
    }

    @MainActor
    func testFailedChangesKeepActualSystemStateAndCanBeRetried() {
        let service = FakeLoginItemService()
        service.shouldFail = true
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertEqual(controller.status, .notRegistered)
        XCTAssertNotNil(controller.errorMessage)
        service.shouldFail = false
        controller.setEnabled(true)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertNil(controller.errorMessage)
        service.shouldFail = true
        controller.setEnabled(false)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertNotNil(controller.errorMessage)
    }

    @MainActor
    func testMissingServiceCanBeRegisteredAgain() {
        let service = FakeLoginItemService()
        service.status = .notFound
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertEqual(service.registerCalls, 1)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemService {
    var status: LoginItemStatus = .notRegistered
    var registrationStatus: LoginItemStatus = .enabled
    var shouldFail = false
    var registerCalls = 0
    var unregisterCalls = 0

    func register() throws {
        registerCalls += 1
        if shouldFail { throw NSError(domain: "StatPeekTests", code: 1) }
        status = registrationStatus
    }

    func unregister() throws {
        unregisterCalls += 1
        if shouldFail { throw NSError(domain: "StatPeekTests", code: 2) }
        status = .notRegistered
    }
}
