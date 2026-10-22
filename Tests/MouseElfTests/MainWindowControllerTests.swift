import XCTest
@testable import MouseElf

@MainActor
private final class FakeMainWindow: MainWindowPresenting {
    var isVisible = true
    var isMiniaturized = false
    var presentations = 0
    var restorations = 0
    func deminiaturize(_ sender: Any?) { restorations += 1; isMiniaturized = false; isVisible = true }
    func makeKeyAndOrderFront(_ sender: Any?) { presentations += 1; isVisible = true }
}

@MainActor
final class MainWindowControllerTests: XCTestCase {
    func testVisibleWindowIsReused() {
        var creations = 0
        var activations = 0
        let controller = MainWindowController(activate: { activations += 1 })
        controller.openNewWindow = { creations += 1 }
        let window = FakeMainWindow()
        controller.register(window)
        XCTAssertTrue(controller.show())
        XCTAssertEqual(window.presentations, 1)
        XCTAssertEqual(creations, 0)
        XCTAssertEqual(activations, 1)
    }

    func testClosedWindowCreatesANewSceneInsteadOfRevivingDisposedContent() {
        var creations = 0
        let controller = MainWindowController(activate: {})
        controller.openNewWindow = { creations += 1 }
        let closedWindow = FakeMainWindow()
        closedWindow.isVisible = false
        controller.register(closedWindow)
        XCTAssertTrue(controller.show())
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(closedWindow.presentations, 0)
    }

    func testReleasedWindowCanBeRecreatedRepeatedly() {
        var creations = 0
        let controller = MainWindowController(activate: {})
        controller.openNewWindow = { creations += 1 }
        for _ in 0..<3 {
            var window: FakeMainWindow? = FakeMainWindow()
            controller.register(window!)
            window = nil
            XCTAssertTrue(controller.show())
        }
        XCTAssertEqual(creations, 3)
    }

    func testMinimizedWindowIsRestoredWithoutCreatingAnotherWindow() {
        var creations = 0
        let controller = MainWindowController(activate: {})
        controller.openNewWindow = { creations += 1 }
        let window = FakeMainWindow()
        window.isVisible = false
        window.isMiniaturized = true
        controller.register(window)
        XCTAssertTrue(controller.show())
        XCTAssertEqual(window.restorations, 1)
        XCTAssertEqual(window.presentations, 1)
        XCTAssertEqual(creations, 0)
    }

    func testUnconfiguredControllerAllowsDefaultReopenHandling() {
        var activations = 0
        let controller = MainWindowController(activate: { activations += 1 })
        XCTAssertFalse(controller.show())
        XCTAssertEqual(activations, 0)
    }
}
