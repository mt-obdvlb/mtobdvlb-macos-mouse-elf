import AppKit
import CoreGraphics

// Local input receiver for manual end-to-end testing. This fixture never emits input events.
@main
enum InputProbeMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = ProbeApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

final class ProbeApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    private let outputURL = URL(fileURLWithPath: "/tmp/mouse-elf-probe.json")
    private var window: NSWindow!
    private var clickButton: NSButton!
    private var textField: NSTextField!
    private var gestureArea: ProbeGestureView!
    private var timer: Timer?
    private var clickCount = 0
    private var scrollMonitor: Any?
    private var receivedScrollEvents = 0
    private var lastScrollWindowNumber = 0
    private var lastScrollLocation = NSPoint.zero
    private var lastScrollFields: [String: Any] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "MouseElfProbe · 本地输入验收"
        window.identifier = NSUserInterfaceItemIdentifier("MouseElfProbeWindow")
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        let root = NSView()
        window.contentView = root
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
        ])

        let title = NSTextField(labelWithString: "输入验收靶场")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        stack.addArrangedSubview(title)
        let subtitle = NSTextField(wrappingLabelWithString: "只接收真实输入，不发送事件，不请求系统权限。")
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)

        clickButton = ProbeButton(title: "已接收点击次数：0", target: self, action: #selector(receivedClick))
        clickButton.bezelStyle = .rounded
        clickButton.controlSize = .large
        clickButton.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        clickButton.setAccessibilityIdentifier("probeClickTarget")
        stack.addArrangedSubview(clickButton)
        clickButton.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        clickButton.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let label = NSTextField(labelWithString: "文本输入目标")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        stack.addArrangedSubview(label)
        textField = NSTextField(string: "")
        textField.placeholderString = "在此接收键盘或 Unicode 文本输入"
        textField.font = .systemFont(ofSize: 15)
        textField.delegate = self
        textField.setAccessibilityIdentifier("probeTextTarget")
        stack.addArrangedSubview(textField)
        textField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        textField.heightAnchor.constraint(equalToConstant: 34).isActive = true

        gestureArea = ProbeGestureView()
        gestureArea.setAccessibilityIdentifier("probeGestureTarget")
        gestureArea.onChange = { [weak self] in self?.writeSnapshot() }
        stack.addArrangedSubview(gestureArea)
        gestureArea.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        gestureArea.heightAnchor.constraint(equalToConstant: 180).isActive = true

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        let hint = NSTextField(labelWithString: "状态：/tmp/mouse-elf-probe.json")
        hint.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        hint.textColor = .secondaryLabelColor
        footer.addArrangedSubview(hint)
        let reset = NSButton(title: "清空计数", target: self, action: #selector(resetProbe))
        reset.bezelStyle = .rounded
        reset.setAccessibilityIdentifier("probeReset")
        footer.addArrangedSubview(reset)
        stack.addArrangedSubview(footer)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        root.layoutSubtreeIfNeeded()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.receivedScrollEvents += 1
            self?.lastScrollWindowNumber = event.windowNumber
            self?.lastScrollLocation = event.locationInWindow
            self?.lastScrollFields = ["phase": event.phase.rawValue, "momentumPhase": event.momentumPhase.rawValue, "precise": event.hasPreciseScrollingDeltas, "deltaY": event.scrollingDeltaY]
            if let cg = event.cgEvent {
                self?.lastScrollFields["cgFlags"] = cg.flags.rawValue
                self?.lastScrollFields["cgLocation"] = ["x": cg.location.x, "y": cg.location.y]
                self?.lastScrollFields["cgUserData"] = cg.getIntegerValueField(.eventSourceUserData)
                self?.lastScrollFields["cgSourceState"] = cg.getIntegerValueField(.eventSourceStateID)
                self?.lastScrollFields["cgSourcePID"] = cg.getIntegerValueField(.eventSourceUnixProcessID)
                if let field = CGEventField(rawValue: 51) { self?.lastScrollFields["cgWindowNumber"] = cg.getIntegerValueField(field) }
                for (name, field) in [("cgDeltaY", CGEventField.scrollWheelEventDeltaAxis1), ("cgPointDeltaY", .scrollWheelEventPointDeltaAxis1), ("cgContinuous", .scrollWheelEventIsContinuous), ("cgScrollPhase", .scrollWheelEventScrollPhase), ("cgTargetPid", .eventTargetUnixProcessID), ("cgWindow", .mouseEventWindowUnderMousePointer), ("cgWindowHandler", .mouseEventWindowUnderMousePointerThatCanHandleThisEvent)] {
                    self?.lastScrollFields[name] = cg.getIntegerValueField(field)
                }
            }
            self?.writeSnapshot()
            return event
        }
        writeSnapshot()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.writeSnapshot() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func receivedClick() {
        clickCount += 1
        clickButton.title = "已接收点击次数：\(clickCount)"
        writeSnapshot()
    }

    @objc private func resetProbe() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        clickCount = 0
        receivedScrollEvents = 0
        clickButton.title = "已接收点击次数：0"
        textField.stringValue = ""
        gestureArea.reset()
        writeSnapshot()
    }

    func controlTextDidChange(_ notification: Notification) { writeSnapshot() }
    func windowDidMove(_ notification: Notification) { writeSnapshot() }
    func windowDidResize(_ notification: Notification) { writeSnapshot() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); writeSnapshot() }

    private func quartzRect(_ rect: NSRect) -> [String: Double] {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let top = mainHeight - rect.maxY
        return ["x": rect.minX, "y": top, "width": rect.width, "height": rect.height, "centerX": rect.midX, "centerY": top + rect.height / 2]
    }

    private func viewRect(_ view: NSView) -> [String: Double] {
        quartzRect(window.convertToScreen(view.convert(view.bounds, to: nil)))
    }

    private func writeSnapshot() {
        guard window != nil, clickButton != nil, textField != nil, gestureArea != nil else { return }
        let state: [String: Any] = [
            "schemaVersion": 1,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "pid": ProcessInfo.processInfo.processIdentifier,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "isActive": NSApp.isActive,
            "windowVisible": window.isVisible,
            "coordinateSystem": "Quartz global points, origin at main display top-left",
            "windowRect": quartzRect(window.frame),
            "buttonRect": viewRect(clickButton),
            "textFieldRect": viewRect(textField),
            "gestureAreaRect": viewRect(gestureArea),
            "clickCount": clickCount,
            "text": textField.stringValue,
            "dragEvents": gestureArea.dragEvents,
            "completedDrags": gestureArea.completedDrags,
            "scrollEvents": gestureArea.scrollEvents,
            "receivedScrollEvents": receivedScrollEvents,
            "lastScrollWindowNumber": lastScrollWindowNumber,
            "lastScrollLocation": ["x": lastScrollLocation.x, "y": lastScrollLocation.y],
            "lastScrollFields": lastScrollFields,
            "scrollDeltaX": gestureArea.scrollDeltaX,
            "scrollDeltaY": gestureArea.scrollDeltaY,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputURL, options: .atomic)
        } catch {
            // Keep receiver behavior intact if a pre-existing /tmp file is not writable.
            NSLog("MouseElfProbe could not save state: %@", error.localizedDescription)
        }
    }
}

final class ProbeButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ProbeGestureView: NSView {
    var onChange: (() -> Void)?
    private(set) var dragEvents = 0
    private(set) var completedDrags = 0
    private(set) var scrollEvents = 0
    private(set) var scrollDeltaX: Double = 0
    private(set) var scrollDeltaY: Double = 0
    private var points: [NSPoint] = []
    private var didDrag = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        border.lineWidth = 1
        border.stroke()
        if points.count > 1 {
            let path = NSBezierPath()
            path.move(to: points[0])
            for point in points.dropFirst() { path.line(to: point) }
            path.lineWidth = 2
            NSColor.systemTeal.setStroke()
            path.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.labelColor]
        ("拖拽 / 滚轮目标区域" as NSString).draw(at: NSPoint(x: 16, y: 16), withAttributes: attributes)
        let detail = "拖拽完成 \(completedDrags) 次 · 移动事件 \(dragEvents) 次\n滚动事件 \(scrollEvents) 次 · ΔX \(Int(scrollDeltaX)) / ΔY \(Int(scrollDeltaY))"
        (detail as NSString).draw(in: NSRect(x: 16, y: 45, width: bounds.width - 32, height: 60), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        points = [convert(event.locationInWindow, from: nil)]
        didDrag = false
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        dragEvents += 1
        points.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
        onChange?()
    }
    override func mouseUp(with event: NSEvent) {
        if didDrag { completedDrags += 1 }
        didDrag = false
        needsDisplay = true
        onChange?()
    }
    override func scrollWheel(with event: NSEvent) {
        scrollEvents += 1
        scrollDeltaX += event.scrollingDeltaX
        scrollDeltaY += event.scrollingDeltaY
        needsDisplay = true
        onChange?()
    }
    func reset() {
        dragEvents = 0; completedDrags = 0; scrollEvents = 0
        scrollDeltaX = 0; scrollDeltaY = 0
        points = []; didDrag = false
        needsDisplay = true
    }
}
