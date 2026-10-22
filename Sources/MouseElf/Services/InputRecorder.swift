import AppKit
import ApplicationServices
import MouseElfCore
import Observation

@MainActor @Observable
final class InputRecorder {
    private(set) var isRecording = false
    private(set) var steps: [ScriptStep] = []
    private(set) var elapsed: Double = 0
    private(set) var error: String?
    /// Automatic stops only. A caller explicitly using stop() already owns saving its result.
    var onFinish: (() -> Void)?

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startedAt: Double = 0
    @ObservationIgnored private var lastAcceptedAt: Double = 0
    @ObservationIgnored private var lastMoveAt: Double = 0
    @ObservationIgnored private var recordMovement = true
    @ObservationIgnored private var recordKeyboard = false
    @ObservationIgnored private var bindings: [HotkeyBinding] = []
    @ObservationIgnored private var suppressedKeys = Set<UInt16>()
    @ObservationIgnored private var heldKeys = Set<UInt16>()
    @ObservationIgnored private var heldButtons = Set<MouseButton>()
    @ObservationIgnored private var physicalModifierKeys = Set<UInt16>()
    @ObservationIgnored private var suppressedModifierKeys = Set<UInt16>()
    @ObservationIgnored private var pendingModifiers: [(step: ScriptStep, time: Double)] = []
    @ObservationIgnored private var lastPoint = CGPoint.zero
    @ObservationIgnored private var ownWindowFrames: [CGRect] = []
    @ObservationIgnored private var lastWindowRefresh: Double = 0
    private let maximumSteps = 10_000

    func start(recordMouseMovement: Bool, recordKeyboard: Bool, hotkeys: [HotkeyAction: HotkeyBinding]) throws {
        guard !isRecording else { throw ValidationError.invalid("录制已在进行。") }
        guard CGPreflightListenEventAccess() else { throw ValidationError.invalid("尚未获得输入监控权限。请在系统设置中授权此应用，再开始录制。") }
        self.recordMovement = recordMouseMovement; self.recordKeyboard = recordKeyboard
        bindings = Array(hotkeys.values)
        steps = []; elapsed = 0; error = nil
        heldKeys.removeAll(); heldButtons.removeAll(); suppressedKeys.removeAll()
        physicalModifierKeys.removeAll(); suppressedModifierKeys.removeAll(); pendingModifiers.removeAll()
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel, .keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<InputRecorder>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { recorder.receive(type: type, event: event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { throw ValidationError.invalid("macOS 无法启动全局录制。请检查输入监控权限；刚授权后可能需要退出并重新打开应用。") }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap); self.tap = nil
            throw ValidationError.invalid("无法创建录制事件源。")
        }
        self.source = source
        startedAt = ProcessInfo.processInfo.systemUptime; lastAcceptedAt = startedAt; lastMoveAt = 0
        lastPoint = QuartzEventDriver.currentMousePosition()
        refreshWindowFrames(now: startedAt)
        isRecording = true
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                self.elapsed = ProcessInfo.processInfo.systemUptime - self.startedAt
            }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    @discardableResult
    func stop() -> [ScriptStep] {
        guard isRecording else { return steps }
        isRecording = false
        let now = ProcessInfo.processInfo.systemUptime
        elapsed = now - startedAt
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; timer?.invalidate(); timer = nil
        // Preserve the final wait, including a stop initiated by a global shortcut.
        var trailing = (now - lastAcceptedAt) * 1000
        while !steps.isEmpty, trailing >= 10, steps.count + heldButtons.count + heldKeys.count < maximumSteps {
            var wait = ScriptStep(kind: .wait); wait.durationMilliseconds = min(trailing, 3_600_000)
            steps.append(wait)
            trailing -= wait.durationMilliseconds
        }
        for button in heldButtons where steps.count < maximumSteps {
            var up = ScriptStep(kind: .mouseUp); up.button = button; up.x = lastPoint.x; up.y = lastPoint.y
            steps.append(up)
        }
        for code in heldKeys.sorted() where steps.count < maximumSteps {
            var up = ScriptStep(kind: .keyUp); up.keyCode = code; steps.append(up)
        }
        heldButtons.removeAll(); heldKeys.removeAll(); suppressedKeys.removeAll()
        physicalModifierKeys.removeAll(); suppressedModifierKeys.removeAll(); pendingModifiers.removeAll()
        return steps
    }

    private func receive(type: CGEventType, event: CGEvent) {
        guard isRecording else { return }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            finishAutomatically("系统暂停了全局事件监听，录制已停止并保留已有步骤。")
            return
        }
        guard event.getIntegerValueField(.eventSourceUserData) != mouseElfSyntheticEventMarker else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let point = event.location
        if type == .flagsChanged {
            receiveModifier(event, at: now)
            return
        }
        if type == .keyDown || type == .keyUp {
            let key = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            guard key <= 126 else { return }
            if key == 53, type == .keyDown { finishAutomatically(nil); return }
            if isHotkey(key: key, flags: event.flags) {
                if type == .keyDown {
                    suppressedKeys.insert(key)
                    for pending in pendingModifiers where pending.step.kind == .keyDown { suppressedModifierKeys.insert(pending.step.keyCode) }
                    pendingModifiers.removeAll()
                } else { suppressedKeys.remove(key) }
                return
            }
            if suppressedKeys.contains(key) {
                if type == .keyUp { suppressedKeys.remove(key) }
                return
            }
            guard recordKeyboard else { return }
            // App edits and shortcut configuration must never become replayed keystrokes.
            if NSApplication.shared.isActive && !heldKeys.contains(key) { return }
            if type == .keyUp && !heldKeys.contains(key) { return }
            flushPendingModifiers()
            guard isRecording else { return }
            var step = ScriptStep(kind: type == .keyDown ? .keyDown : .keyUp)
            step.keyCode = key; step.modifiers = event.flags.rawValue
            if type == .keyDown { heldKeys.insert(key) } else { heldKeys.remove(key) }
            append(step, at: now)
            return
        }

        if now - lastWindowRefresh > 0.3 { refreshWindowFrames(now: now) }
        // A background window's rectangle may be covered by another app. Only
        // suppress our own foreground controls, never the browser above them.
        let isOwnWindow = NSApplication.shared.isActive && ownWindowFrames.contains { $0.contains(point) }
        let button: MouseButton = switch type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: .right
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged: .middle
        default: .left
        }
        var step: ScriptStep
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard !isOwnWindow else { return }
            heldButtons.insert(button)
            step = ScriptStep(kind: .mouseDown); step.button = button
            step.clickCount = max(1, min(2, Int(event.getIntegerValueField(.mouseEventClickState))))
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard heldButtons.contains(button) else { return }
            heldButtons.remove(button)
            step = ScriptStep(kind: .mouseUp); step.button = button
            step.clickCount = max(1, min(2, Int(event.getIntegerValueField(.mouseEventClickState))))
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let dragging = !heldButtons.isEmpty
            guard (recordMovement || dragging), (!isOwnWindow || dragging), now - lastMoveAt >= (dragging ? 0.016 : 0.033) else { return }
            lastMoveAt = now
            step = ScriptStep(kind: .move)
        case .scrollWheel:
            guard !isOwnWindow else { return }
            step = ScriptStep(kind: .scroll)
            step.scrollX = Int32(max(-10_000, min(10_000, event.getIntegerValueField(.scrollWheelEventDeltaAxis2))))
            step.scrollY = Int32(max(-10_000, min(10_000, event.getIntegerValueField(.scrollWheelEventDeltaAxis1))))
            guard step.scrollX != 0 || step.scrollY != 0 else { return }
        default: return
        }
        flushPendingModifiers()
        guard isRecording else { return }
        step.x = point.x; step.y = point.y; step.modifiers = event.flags.rawValue; lastPoint = point
        append(step, at: now)
    }

    private func receiveModifier(_ event: CGEvent, at now: Double) {
        guard recordKeyboard else { return }
        let key = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        let mask: CGEventFlags
        switch key {
        case 54, 55: mask = .maskCommand
        case 56, 60: mask = .maskShift
        case 58, 61: mask = .maskAlternate
        case 59, 62: mask = .maskControl
        case 57: mask = .maskAlphaShift
        case 63: mask = .maskSecondaryFn
        default: return
        }
        let down = !physicalModifierKeys.contains(key) && event.flags.contains(mask)
        if down { physicalModifierKeys.insert(key) } else { physicalModifierKeys.remove(key) }
        if suppressedModifierKeys.contains(key) {
            if !down { suppressedModifierKeys.remove(key) }
            return
        }
        // Preserve a release for an externally recorded modifier after focus
        // changes; modifier presses made in our own editor are never recorded.
        guard !NSApplication.shared.isActive || (!down && heldKeys.contains(key)) else { return }
        if !down && !heldKeys.contains(key) && !pendingModifiers.contains(where: { $0.step.keyCode == key && $0.step.kind == .keyDown }) { return }
        var step = ScriptStep(kind: down ? .keyDown : .keyUp)
        step.keyCode = key; step.modifiers = event.flags.rawValue
        pendingModifiers.append((step, now))
        // Hold fresh modifier downs until the next action: if it is a control hotkey,
        // its modifiers can be discarded together with the shortcut itself.
        if !down { flushPendingModifiers() }
    }

    private func flushPendingModifiers() {
        let pending = pendingModifiers; pendingModifiers.removeAll()
        for value in pending {
            guard isRecording else { return }
            if value.step.kind == .keyDown { heldKeys.insert(value.step.keyCode) }
            else { heldKeys.remove(value.step.keyCode) }
            append(value.step, at: value.time)
        }
    }

    private func append(_ source: ScriptStep, at now: Double) {
        var step = source
        var delay = max(0, (now - lastAcceptedAt) * 1000)
        // A recording can remain open for hours; split long idle gaps into valid waits.
        while delay > 3_600_000, steps.count + heldKeys.count + heldButtons.count + 2 < maximumSteps {
            var wait = ScriptStep(kind: .wait); wait.durationMilliseconds = 3_600_000
            steps.append(wait); delay -= 3_600_000
        }
        step.delayMilliseconds = min(delay, 3_600_000)
        steps.append(step); lastAcceptedAt = now; elapsed = now - startedAt
        if steps.count + heldKeys.count + heldButtons.count >= maximumSteps - 1 {
            finishAutomatically("录制已达到 10,000 步上限，已有步骤已保留。")
        }
    }

    private func isHotkey(key: UInt16, flags: CGEventFlags) -> Bool {
        var modifiers: UInt32 = 0
        if flags.contains(.maskCommand) { modifiers |= 0x100 }
        if flags.contains(.maskShift) { modifiers |= 0x200 }
        if flags.contains(.maskAlternate) { modifiers |= 0x800 }
        if flags.contains(.maskControl) { modifiers |= 0x1000 }
        return bindings.contains { $0.keyCode == UInt32(key) && $0.modifiers == modifiers }
    }

    private func refreshWindowFrames(now: Double) {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        ownWindowFrames = NSApplication.shared.windows.filter(\.isVisible).map {
            let frame = $0.frame
            return CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
        }
        lastWindowRefresh = now
    }

    private func finishAutomatically(_ message: String?) {
        guard isRecording else { return }
        error = message
        stop()
        onFinish?()
    }
}
