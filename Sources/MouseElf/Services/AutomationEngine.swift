import AppKit
import ApplicationServices
import MouseElfCore
import Observation

let mouseElfSyntheticEventMarker: Int64 = 0x4D_45_4C_46

enum AutomationPhase: String { case idle, countdown, running, paused }
enum AutomationMode: String { case clicking, playback }

enum AutomationEvent: Equatable {
    case move(CGPoint, MouseButton?, UInt64 = 0)
    case mouseDown(MouseButton, CGPoint, Int, UInt64 = 0)
    case mouseUp(MouseButton, CGPoint, Int, UInt64 = 0)
    case scroll(Int32, Int32, CGPoint, UInt64 = 0)
    case keyDown(UInt16, UInt64)
    case keyUp(UInt16, UInt64)
    case text(String)
}

@MainActor
protocol AutomationEventDriver: AnyObject {
    var accessibilityGranted: Bool { get }
    var mousePosition: CGPoint { get }
    var screenBounds: [CGRect] { get }
    func post(_ event: AutomationEvent) throws
}

enum AutomationError: LocalizedError {
    case busy, accessibilityDenied, noSteps, eventCreationFailed, scrollTargetUnavailable, scrollRoutingUnavailable
    var errorDescription: String? {
        switch self {
        case .busy: "请先停止当前任务。"
        case .accessibilityDenied: "尚未获得辅助功能权限。请在设置中授权此应用，再重新启动任务。"
        case .noSteps: "脚本中没有已启用的步骤。"
        case .eventCreationFailed: "macOS 无法创建输入事件，任务已停止。"
        case .scrollTargetUnavailable: "滚动坐标下没有可定位的其它应用窗口。请将坐标设置在目标窗口内。"
        case .scrollRoutingUnavailable: "当前系统无法关联滚轮事件的窗口坐标，回放已停止。"
        }
    }
}

@MainActor
final class QuartzEventDriver: AutomationEventDriver {
    private static let eventSource: CGEventSource? = {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.userData = mouseElfSyntheticEventMarker
        source?.localEventsSuppressionInterval = 0
        return source
    }()
    private typealias SetWindowLocation = @convention(c) (CGEvent, CGPoint) -> Void
    private static let setWindowLocation: SetWindowLocation? = {
        guard let handle = dlopen(nil, RTLD_LAZY), let symbol = dlsym(handle, "CGEventSetWindowLocation") else { return nil }
        return unsafeBitCast(symbol, to: SetWindowLocation.self)
    }()
    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    var mousePosition: CGPoint { Self.currentMousePosition() }
    var screenBounds: [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return [CGDisplayBounds(CGMainDisplayID())] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [CGDisplayBounds(CGMainDisplayID())] }
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }
    static func currentMousePosition() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

    func post(_ action: AutomationEvent) throws {
        guard accessibilityGranted else { throw AutomationError.accessibilityDenied }
        let source = Self.eventSource
        let event: CGEvent?
        switch action {
        case let .move(point, button, modifiers):
            let type: CGEventType = switch button { case .left: .leftMouseDragged; case .right: .rightMouseDragged; case .middle: .otherMouseDragged; case nil: .mouseMoved }
            event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: cgButton(button ?? .left))
            event?.flags = CGEventFlags(rawValue: modifiers)
        case let .mouseDown(button, point, count, modifiers):
            event = CGEvent(mouseEventSource: source, mouseType: mouseType(button, down: true), mouseCursorPosition: point, mouseButton: cgButton(button))
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            event?.flags = CGEventFlags(rawValue: modifiers)
        case let .mouseUp(button, point, count, modifiers):
            event = CGEvent(mouseEventSource: source, mouseType: mouseType(button, down: false), mouseCursorPosition: point, mouseButton: cgButton(button))
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            event?.flags = CGEventFlags(rawValue: modifiers)
        case let .scroll(x, y, point, modifiers):
            let target = try scrollTarget(at: point)
            // Precise scrolling is a complete gesture. Bare phase-less pixel
            // events can be consumed by wheel smoothing tools without delivery.
            let events = try [CGScrollPhase.began, .changed, .ended].map { phase in
                try Self.makeScrollEvent(x: phase == .changed ? x : 0, y: phase == .changed ? y : 0, point: point, modifiers: modifiers, windowID: target.windowID, windowBounds: target.bounds, phase: phase)
            }
            for event in events {
                event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(target.pid))
                event.postToPid(target.pid)
            }
            return
        case let .keyDown(code, modifiers):
            event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
            event?.flags = CGEventFlags(rawValue: modifiers)
        case let .keyUp(code, modifiers):
            event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
            event?.flags = CGEventFlags(rawValue: modifiers)
        case let .text(text):
            // Small UTF-16 chunks keep long text below Quartz's per-event limit.
            let units = Array(text.utf16)
            var offset = 0
            while offset < units.count {
                var end = min(offset + 20, units.count)
                if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }
                let chunk = Array(units[offset..<end])
                for down in [true, false] {
                    guard let key = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { throw AutomationError.eventCreationFailed }
                    key.flags = []
                    chunk.withUnsafeBufferPointer { key.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress) }
                    emit(key)
                }
                offset = end
            }
            return
        }
        guard let event else { throw AutomationError.eventCreationFailed }
        emit(event)
    }

    private func emit(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: mouseElfSyntheticEventMarker)
        event.post(tap: .cghidEventTap)
    }

    static func makeScrollEvent(x: Int32, y: Int32, point: CGPoint, modifiers: UInt64, windowID: CGWindowID, windowBounds: CGRect, phase: CGScrollPhase = .changed) throws -> CGEvent {
        guard let stampWindowLocation = setWindowLocation else { throw AutomationError.scrollRoutingUnavailable }
        let source = eventSource
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: x == 0 ? 1 : 2, wheel1: y * 10, wheel2: x * 10, wheel3: 0) else { throw AutomationError.eventCreationFailed }
        event.location = point
        let modifierMask = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
        event.flags = CGEventFlags(rawValue: (event.flags.rawValue & ~modifierMask) | modifiers)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        event.timestamp = DispatchTime.now().uptimeNanoseconds
        event.setIntegerValueField(.eventSourceUserData, value: mouseElfSyntheticEventMarker)
        // AppKit's window-number field is not named in the public CGEventField
        // enum. 91/92 alone leave NSEvent.windowNumber == 0, silently dropping
        // process-directed wheel events. Keep this bridge covered by a Cocoa
        // round-trip test, and recheck it when updating the macOS SDK.
        event.setIntegerValueField(CGEventField(rawValue: 51)!, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        // Process-directed events need both screen and window-local locations.
        // Resolve the SPI at runtime and fail explicitly if the OS removes it.
        stampWindowLocation(event, CGPoint(x: point.x - windowBounds.minX, y: point.y - windowBounds.minY))
        return event
    }
    private func scrollTarget(at point: CGPoint) throws -> (pid: pid_t, windowID: CGWindowID, bounds: CGRect) {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { throw AutomationError.scrollTargetUnavailable }
        return try Self.resolveScrollTarget(at: point, windows: windows, currentProcessID: ProcessInfo.processInfo.processIdentifier)
    }

    static func resolveScrollTarget(at point: CGPoint, windows: [[String: Any]], currentProcessID: pid_t) throws -> (pid: pid_t, windowID: CGWindowID, bounds: CGRect) {
        // The on-screen list is ordered front to back. Ignore invisible windows,
        // this app's controls, and high-layer pointer / screen overlay utilities.
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  let number = window[kCGWindowNumber as String] as? NSNumber,
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber,
                  let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  owner.int32Value > 0,
                  number.uint32Value != kCGNullWindowID, (0...10).contains(layer.intValue),
                  alpha.doubleValue > 0, bounds.contains(point) else { continue }
            // Do not scroll a hidden window underneath our foreground controls.
            guard owner.int32Value != currentProcessID else { throw AutomationError.scrollTargetUnavailable }
            return (owner.int32Value, number.uint32Value, bounds)
        }
        throw AutomationError.scrollTargetUnavailable
    }
    private func cgButton(_ button: MouseButton) -> CGMouseButton { switch button { case .left: .left; case .right: .right; case .middle: .center } }
    private func mouseType(_ button: MouseButton, down: Bool) -> CGEventType {
        switch button { case .left: down ? .leftMouseDown : .leftMouseUp; case .right: down ? .rightMouseDown : .rightMouseUp; case .middle: down ? .otherMouseDown : .otherMouseUp }
    }
}

@MainActor @Observable
final class AutomationEngine {
    private(set) var phase: AutomationPhase = .idle
    var isActive: Bool { phase != .idle }
    private(set) var completedActions = 0
    private(set) var cycle = 0
    private(set) var activeStepID: UUID?
    private(set) var status = "就绪"
    private(set) var error: String?
    private(set) var mode: AutomationMode?
    var onFinish: (() -> Void)?

    @ObservationIgnored private let driver: any AutomationEventDriver
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var runID: UUID?
    @ObservationIgnored private var resumedPhase: AutomationPhase = .running
    @ObservationIgnored private var heldButtons = Set<MouseButton>()
    @ObservationIgnored private var heldKeys: [UInt16: UInt64] = [:]
    @ObservationIgnored private var safetyKeys: SafetyKeyMonitor?
    @ObservationIgnored private var cornerFailsafe = true
    @ObservationIgnored private let monitorsSafetyKeys: Bool

    init(driver: (any AutomationEventDriver)? = nil, monitorsSafetyKeys: Bool = true) {
        self.driver = driver ?? QuartzEventDriver(); self.monitorsSafetyKeys = monitorsSafetyKeys
    }
    static func currentMousePosition() -> CGPoint { QuartzEventDriver.currentMousePosition() }

    func startClicking(_ configuration: ClickConfiguration, cornerFailsafe: Bool) throws {
        try configuration.validate()
        try prepare(mode: .clicking, cornerFailsafe: cornerFailsafe)
        let id = runID!
        task = Task { [weak self] in
            guard let self else { return }
            await self.execute(id: id) {
                try await self.countdown(configuration.startDelay)
                while configuration.repeatCount == 0 || self.completedActions < configuration.repeatCount {
                    try await self.wait(milliseconds: 0)
                    self.cycle = self.completedActions + 1
                    let point = configuration.useFixedPosition ? CGPoint(x: configuration.x, y: configuration.y) : self.driver.mousePosition
                    try await self.click(button: configuration.button, point: point, count: configuration.clickCount)
                    self.completedActions += 1
                    self.status = "已点击 \(self.completedActions) 次"
                    if configuration.repeatCount != 0 && self.completedActions >= configuration.repeatCount { break }
                    try await self.wait(milliseconds: configuration.intervalMilliseconds)
                }
            }
        }
    }

    func startPlayback(_ script: MouseScript, startDelay: Double, cornerFailsafe: Bool) throws {
        try script.validate()
        guard startDelay.isFinite, (0...60).contains(startDelay) else { throw ValidationError.invalid("启动延迟应在 0–60 秒之间。") }
        guard !script.enabledSteps.isEmpty else { throw AutomationError.noSteps }
        try prepare(mode: .playback, cornerFailsafe: cornerFailsafe)
        let id = runID!
        task = Task { [weak self] in
            guard let self else { return }
            await self.execute(id: id) {
                try await self.countdown(startDelay)
                while script.loopCount == 0 || self.cycle < script.loopCount {
                    self.cycle += 1
                    for step in script.enabledSteps {
                        self.activeStepID = step.id
                        self.status = "第 \(self.cycle) 轮 · \(step.displayTitle)"
                        try await self.wait(milliseconds: step.delayMilliseconds / script.speed)
                        try await self.perform(step, speed: script.speed)
                        self.completedActions += 1
                    }
                    // Incomplete down/up pairs must never leak across script iterations.
                    self.releaseHeldInputs()
                }
            }
        }
    }

    func pauseResume() {
        guard isActive else { return }
        if phase == .paused { phase = resumedPhase; status = "继续执行" }
        else { resumedPhase = phase; phase = .paused; status = "已暂停" }
    }

    func stop() {
        guard isActive else { return }
        task?.cancel()
        finish(status: "已停止")
    }

    private func prepare(mode: AutomationMode, cornerFailsafe: Bool) throws {
        guard !isActive else { throw AutomationError.busy }
        guard driver.accessibilityGranted else { throw AutomationError.accessibilityDenied }
        completedActions = 0; cycle = 0; activeStepID = nil; error = nil
        self.cornerFailsafe = cornerFailsafe; self.mode = mode
        runID = UUID(); phase = .countdown; status = "准备启动"
        if monitorsSafetyKeys {
            safetyKeys = SafetyKeyMonitor { [weak self] in self?.stop() }
            safetyKeys?.start()
        }
    }

    private func execute(id: UUID, body: () async throws -> Void) async {
        do {
            try await body()
            guard runID == id else { return }
            finish(status: "执行完成")
        } catch is CancellationError {
            if runID == id { finish(status: "已停止") }
        } catch {
            guard runID == id else { return }
            self.error = error.localizedDescription
            finish(status: "执行失败")
        }
    }

    private func countdown(_ seconds: Double) async throws {
        var remaining = seconds
        while remaining > 0 {
            if phase != .paused { status = "\(Int(ceil(remaining))) 秒后开始" }
            let part = min(remaining, 0.1)
            try await wait(milliseconds: part * 1000)
            remaining -= part
        }
        try await wait(milliseconds: 0)
        phase = .running
    }

    private func wait(milliseconds: Double) async throws {
        // Even a script made entirely of zero-delay moves must yield to Stop and hotkeys.
        await Task.yield()
        var remaining = milliseconds / 1000
        repeat {
            try Task.checkCancellation()
            guard isActive else { throw CancellationError() }
            if cornerFailsafe && isAtScreenCorner() {
                status = "已触发屏幕角落安全停止"
                finish(status: status)
                throw CancellationError()
            }
            if phase == .paused {
                try await Task.sleep(for: .milliseconds(20))
                continue
            }
            guard remaining > 0 else { return }
            let chunk = min(remaining, 0.02)
            let started = ProcessInfo.processInfo.systemUptime
            try await Task.sleep(for: .seconds(chunk))
            // Time spent paused does not consume a pending delay.
            if phase != .paused { remaining -= ProcessInfo.processInfo.systemUptime - started }
        } while true
    }

    private func isAtScreenCorner() -> Bool {
        let point = driver.mousePosition
        return driver.screenBounds.contains { bounds in
            let nearX = abs(point.x - bounds.minX) <= 3 || abs(point.x - (bounds.maxX - 1)) <= 3
            let nearY = abs(point.y - bounds.minY) <= 3 || abs(point.y - (bounds.maxY - 1)) <= 3
            return nearX && nearY
        }
    }

    private func perform(_ step: ScriptStep, speed: Double) async throws {
        let point = CGPoint(x: step.x, y: step.y)
        switch step.kind {
        case .move: try driver.post(.move(point, heldButtons.first, step.modifiers))
        case .click: try await click(button: step.button, point: point, count: step.clickCount, modifiers: step.modifiers)
        case .mouseDown: try driver.post(.mouseDown(step.button, point, step.clickCount, step.modifiers)); heldButtons.insert(step.button)
        case .mouseUp: try driver.post(.mouseUp(step.button, point, step.clickCount, step.modifiers)); heldButtons.remove(step.button)
        case .scroll: try driver.post(.scroll(step.scrollX, step.scrollY, point, step.modifiers))
        case .wait: try await wait(milliseconds: step.durationMilliseconds / speed)
        case .keyPress:
            try driver.post(.keyDown(step.keyCode, step.modifiers)); heldKeys[step.keyCode] = step.modifiers
            try driver.post(.keyUp(step.keyCode, step.modifiers)); heldKeys.removeValue(forKey: step.keyCode)
        case .keyDown: try driver.post(.keyDown(step.keyCode, step.modifiers)); heldKeys[step.keyCode] = step.modifiers
        case .keyUp: try driver.post(.keyUp(step.keyCode, step.modifiers)); heldKeys.removeValue(forKey: step.keyCode)
        case .text: try driver.post(.text(step.text))
        }
    }

    private func click(button: MouseButton, point: CGPoint, count: Int, modifiers: UInt64 = 0) async throws {
        for clickState in 1...count {
            if clickState > 1 { try await wait(milliseconds: 60) }
            try driver.post(.mouseDown(button, point, clickState, modifiers)); heldButtons.insert(button)
            try driver.post(.mouseUp(button, point, clickState, modifiers)); heldButtons.remove(button)
        }
    }

    private func releaseHeldInputs() {
        let point = driver.mousePosition
        var releaseErrors: [String] = []
        for button in heldButtons {
            do { try driver.post(.mouseUp(button, point, 1)) } catch { releaseErrors.append(error.localizedDescription) }
        }
        // Clearing flags on cleanup also releases the logical modifier state.
        for key in heldKeys.keys.sorted() {
            do { try driver.post(.keyUp(key, 0)) } catch { releaseErrors.append(error.localizedDescription) }
        }
        heldButtons.removeAll(); heldKeys.removeAll()
        if let releaseError = releaseErrors.first {
            let notice = "未能松开部分输入：\(releaseError) 请手动松开相关按键或鼠标。"
            error = error.map { $0 + "\n" + notice } ?? notice
        }
    }

    private func finish(status: String) {
        runID = nil; task = nil
        releaseHeldInputs()
        safetyKeys?.stop(); safetyKeys = nil
        phase = .idle; mode = nil; activeStepID = nil; self.status = status
        onFinish?()
    }
}

/// Keeps Escape available in other apps while a task is running; neither monitor consumes it.
@MainActor
final class SafetyKeyMonitor {
    private var local: Any?
    private var global: Any?
    private let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler }
    func start() {
        stop()
        global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, event.cgEvent?.getIntegerValueField(.eventSourceUserData) != mouseElfSyntheticEventMarker else { return }
            MainActor.assumeIsolated { self?.handler() }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, event.cgEvent?.getIntegerValueField(.eventSourceUserData) != mouseElfSyntheticEventMarker {
                MainActor.assumeIsolated { self?.handler() }
            }
            return event
        }
    }
    func stop() {
        if let local { NSEvent.removeMonitor(local) }; if let global { NSEvent.removeMonitor(global) }
        local = nil; global = nil
    }
}
