import XCTest
import CoreGraphics
import AppKit
import MouseElfCore
@testable import MouseElf

@MainActor
private final class FakeInputDriver: AutomationEventDriver {
    var accessibilityGranted = true
    var mousePosition = CGPoint(x: 100, y: 100)
    var screenBounds = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
    var events: [AutomationEvent] = []
    var failNext = false
    func post(_ event: AutomationEvent) throws {
        if failNext { failNext = false; throw AutomationError.eventCreationFailed }
        events.append(event)
    }
}

@MainActor
final class EngineTests: XCTestCase {
    func testScrollEventHasCocoaWindowIdentityAndPreciseDeltas() throws {
        let event = try QuartzEventDriver.makeScrollEvent(x: 2, y: -4, point: CGPoint(x: 300, y: 400), modifiers: CGEventFlags.maskShift.rawValue, windowID: 123, windowBounds: CGRect(x: 250, y: 300, width: 800, height: 600))
        let cocoa = try XCTUnwrap(NSEvent(cgEvent: event))
        XCTAssertEqual(cocoa.type, .scrollWheel)
        XCTAssertEqual(cocoa.windowNumber, 123)
        XCTAssertTrue(cocoa.hasPreciseScrollingDeltas)
        XCTAssertEqual(cocoa.scrollingDeltaY, -40)
        XCTAssertEqual(cocoa.scrollingDeltaX, 20)
        XCTAssertEqual(cocoa.phase, .changed)
        XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), mouseElfSyntheticEventMarker)
        XCTAssertTrue(cocoa.modifierFlags.contains(.shift))
    }

    func testScrollGestureEndsWithZeroDelta() throws {
        let event = try QuartzEventDriver.makeScrollEvent(x: 0, y: 0, point: CGPoint(x: 300, y: 400), modifiers: 0, windowID: 123, windowBounds: CGRect(x: 250, y: 300, width: 800, height: 600), phase: .ended)
        let cocoa = try XCTUnwrap(NSEvent(cgEvent: event))
        XCTAssertEqual(cocoa.phase, .ended)
        XCTAssertEqual(cocoa.scrollingDeltaY, 0)
        XCTAssertEqual(cocoa.scrollingDeltaX, 0)
        XCTAssertEqual(cocoa.windowNumber, 123)
    }
    private func window(pid: Int32, id: UInt32, layer: Int = 0, alpha: Double = 1, bounds: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)) -> [String: Any] {
        [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowNumber as String: NSNumber(value: id), kCGWindowLayer as String: NSNumber(value: layer), kCGWindowAlpha as String: NSNumber(value: alpha), kCGWindowBounds as String: bounds.dictionaryRepresentation]
    }

    func testScrollTargetsFrontFloatingWindowAndIgnoresPointerOverlay() throws {
        let target = try QuartzEventDriver.resolveScrollTarget(at: CGPoint(x: 100, y: 100), windows: [window(pid: 11, id: 1, layer: 1000), window(pid: 12, id: 2, layer: 3), window(pid: 13, id: 3)], currentProcessID: 99)
        XCTAssertEqual(target.pid, 12)
        XCTAssertEqual(target.windowID, 2)
    }

    func testScrollDoesNotTargetWindowHiddenUnderOurControls() {
        XCTAssertThrowsError(try QuartzEventDriver.resolveScrollTarget(at: CGPoint(x: 100, y: 100), windows: [window(pid: 99, id: 1), window(pid: 13, id: 2)], currentProcessID: 99))
    }

    func testScrollSupportsNegativeDisplayCoordinatesAndRejectsNoTarget() throws {
        let target = try QuartzEventDriver.resolveScrollTarget(at: CGPoint(x: -200, y: 100), windows: [window(pid: 11, id: 1, alpha: 0), window(pid: 12, id: 2, bounds: CGRect(x: -1280, y: 0, width: 1280, height: 1024))], currentProcessID: 99)
        XCTAssertEqual(target.pid, 12)
        XCTAssertThrowsError(try QuartzEventDriver.resolveScrollTarget(at: CGPoint(x: 9000, y: 0), windows: [window(pid: 11, id: 1)], currentProcessID: 99))
    }

    private func engine(_ driver: FakeInputDriver) -> AutomationEngine {
        AutomationEngine(driver: driver, monitorsSafetyKeys: false)
    }

    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("状态未在 1 秒内到达", file: file, line: line)
    }

    func testCompletesAndProducesDoubleClickStates() async throws {
        let driver = FakeInputDriver()
        let subject = self.engine(driver)
        var config = ClickConfiguration(); config.startDelay = 0; config.repeatCount = 1; config.clickCount = 2
        try subject.startClicking(config, cornerFailsafe: true)
        await waitUntil { !subject.isActive }
        XCTAssertEqual(subject.phase, .idle)
        XCTAssertNil(subject.mode)
        XCTAssertNil(subject.activeStepID)
        XCTAssertEqual(subject.completedActions, 1)
        XCTAssertEqual(driver.events, [.mouseDown(.left, driver.mousePosition, 1), .mouseUp(.left, driver.mousePosition, 1), .mouseDown(.left, driver.mousePosition, 2), .mouseUp(.left, driver.mousePosition, 2)])
    }

    func testCancelCountdownNeverProducesInputAndOldTaskCannotFinishNewRun() async throws {
        let driver = FakeInputDriver()
        let actual = engine(driver)
        var finishes = 0; actual.onFinish = { finishes += 1 }
        var config = ClickConfiguration(); config.startDelay = 30; config.repeatCount = 1
        try actual.startClicking(config, cornerFailsafe: false)
        actual.stop()
        XCTAssertTrue(driver.events.isEmpty)
        config.startDelay = 0
        try actual.startClicking(config, cornerFailsafe: false)
        await waitUntil { !actual.isActive }
        XCTAssertEqual(actual.completedActions, 1)
        XCTAssertEqual(finishes, 2)
        XCTAssertEqual(driver.events.count, 2)
    }

    func testPausesPendingWaitAndContinues() async throws {
        let driver = FakeInputDriver()
        let actual = engine(driver)
        var wait = ScriptStep(kind: .wait); wait.durationMilliseconds = 160
        var script = MouseScript(name: "暂停"); script.steps = [wait, ScriptStep(kind: .click)]
        try actual.startPlayback(script, startDelay: 0, cornerFailsafe: false)
        await waitUntil { actual.phase == .running }
        actual.pauseResume()
        try await Task.sleep(for: .milliseconds(220))
        XCTAssertEqual(actual.phase, .paused)
        XCTAssertTrue(driver.events.isEmpty)
        actual.pauseResume()
        await waitUntil { !actual.isActive }
        XCTAssertEqual(actual.completedActions, 2)
        XCTAssertEqual(driver.events.count, 2)
    }

    func testStopCancelsLongWaitAndReleasesHeldInputs() async throws {
        let driver = FakeInputDriver()
        let actual = engine(driver)
        var key = ScriptStep(kind: .keyDown); key.keyCode = 0; key.modifiers = 1 << 20
        var wait = ScriptStep(kind: .wait); wait.durationMilliseconds = 3_600_000
        var script = MouseScript(name: "持有输入"); script.steps = [ScriptStep(kind: .mouseDown), key, wait]
        try actual.startPlayback(script, startDelay: 0, cornerFailsafe: false)
        await waitUntil { actual.completedActions == 2 }
        actual.stop()
        XCTAssertEqual(actual.phase, .idle)
        XCTAssertEqual(driver.events.suffix(2), [.mouseUp(.left, driver.mousePosition, 1), .keyUp(0, 0)])
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(driver.events.count, 4)
    }

    func testMutualExclusionAndDeniedPermission() async throws {
        let driver = FakeInputDriver()
        let subject = engine(driver)
        try subject.startClicking(ClickConfiguration(), cornerFailsafe: false)
        var script = MouseScript(name: "脚本"); script.steps = [ScriptStep(kind: .click)]
        XCTAssertThrowsError(try subject.startPlayback(script, startDelay: 0, cornerFailsafe: false))
        subject.stop()
        driver.accessibilityGranted = false
        XCTAssertThrowsError(try subject.startClicking(ClickConfiguration(), cornerFailsafe: false))
        XCTAssertFalse(subject.isActive)
        XCTAssertTrue(driver.events.isEmpty)
    }

    func testFailureReleasesHeldInputsAndResetsState() async throws {
        let driver = FakeInputDriver()
        let subject = engine(driver)
        var wait = ScriptStep(kind: .wait); wait.durationMilliseconds = 120
        var script = MouseScript(name: "失败清理"); script.steps = [ScriptStep(kind: .mouseDown), wait, ScriptStep(kind: .move)]
        try subject.startPlayback(script, startDelay: 0, cornerFailsafe: false)
        await waitUntil { subject.completedActions == 1 }
        driver.failNext = true
        await waitUntil { !subject.isActive }
        XCTAssertNotNil(subject.error)
        XCTAssertEqual(driver.events.last, .mouseUp(.left, driver.mousePosition, 1))
        XCTAssertNil(subject.activeStepID)
    }

    func testCornerStopsDuringWaitIncludingSecondaryDisplay() async throws {
        let driver = FakeInputDriver()
        let subject = engine(driver)
        driver.screenBounds.append(CGRect(x: -1280, y: 0, width: 1280, height: 1024))
        var config = ClickConfiguration(); config.startDelay = 30
        try subject.startClicking(config, cornerFailsafe: true)
        driver.mousePosition = CGPoint(x: -1280, y: 0)
        await waitUntil { !subject.isActive }
        XCTAssertTrue(subject.status.contains("安全停止"))
        XCTAssertTrue(driver.events.isEmpty)
    }

    func testZeroDelayInfiniteScriptCanBeStoppedAndDragUsesHeldButton() async throws {
        let driver = FakeInputDriver()
        let subject = engine(driver)
        var script = MouseScript(name: "拖动"); script.loopCount = 0
        var move = ScriptStep(kind: .move); move.x = 80; move.y = 90
        script.steps = [ScriptStep(kind: .mouseDown), move]
        try subject.startPlayback(script, startDelay: 0, cornerFailsafe: false)
        await waitUntil { subject.completedActions >= 2 }
        subject.stop()
        XCTAssertTrue(driver.events.contains(.move(CGPoint(x: 80, y: 90), .left)))
        XCTAssertEqual(subject.phase, .idle)
    }

    func testModifierMouseAndScrollFlagsSurvivePlayback() async throws {
        let driver = FakeInputDriver()
        let subject = engine(driver)
        var click = ScriptStep(kind: .click); click.x = 300; click.y = -20; click.modifiers = 1 << 20
        var scroll = ScriptStep(kind: .scroll); scroll.x = 400; scroll.y = 200; scroll.modifiers = 1 << 17
        var script = MouseScript(name: "修饰键输入"); script.steps = [click, scroll]
        try subject.startPlayback(script, startDelay: 0, cornerFailsafe: false)
        await waitUntil { !subject.isActive }
        XCTAssertEqual(driver.events, [.mouseDown(.left, CGPoint(x: 300, y: -20), 1, 1 << 20), .mouseUp(.left, CGPoint(x: 300, y: -20), 1, 1 << 20), .scroll(0, -3, CGPoint(x: 400, y: 200), 1 << 17)])
    }

    func testNormalCompletionReleasesUnmatchedHeldKey() async throws {
        let driver = FakeInputDriver()
        let subject = engine(driver)
        var key = ScriptStep(kind: .keyDown); key.keyCode = 55; key.modifiers = 1 << 20
        var script = MouseScript(name: "自动释放"); script.steps = [key]; script.loopCount = 2
        try subject.startPlayback(script, startDelay: 0, cornerFailsafe: false)
        await waitUntil { !subject.isActive }
        XCTAssertEqual(subject.cycle, 2)
        XCTAssertEqual(driver.events, [.keyDown(55, 1 << 20), .keyUp(55, 0), .keyDown(55, 1 << 20), .keyUp(55, 0)])
    }
}
