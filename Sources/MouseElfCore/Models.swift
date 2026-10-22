import Foundation

public enum MouseButton: String, Codable, CaseIterable, Identifiable, Sendable {
    case left, right, middle
    public var id: String { rawValue }
    public var title: String { switch self { case .left: "左键"; case .right: "右键"; case .middle: "中键" } }
}

public enum ActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case move, click, mouseDown, mouseUp, scroll, wait, keyPress, keyDown, keyUp, text
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .move: "移动鼠标"; case .click: "点击"; case .mouseDown: "按下鼠标"; case .mouseUp: "松开鼠标"
        case .scroll: "滚动"; case .wait: "等待"; case .keyPress: "键盘快捷键"; case .keyDown: "按下按键"
        case .keyUp: "松开按键"; case .text: "输入文本"
        }
    }
    public var systemImage: String {
        switch self {
        case .move: "cursorarrow.motionlines"; case .click: "cursorarrow.click"; case .mouseDown: "computermouse.fill"
        case .mouseUp: "computermouse"; case .scroll: "arrow.up.arrow.down"; case .wait: "clock"
        case .keyPress, .keyDown, .keyUp: "keyboard"; case .text: "text.cursor"
        }
    }
    public var usesPosition: Bool { [.move, .click, .mouseDown, .mouseUp, .scroll].contains(self) }
    public var usesKey: Bool { [.keyPress, .keyDown, .keyUp].contains(self) }
}

public struct ScriptStep: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var enabled: Bool = true
    public var kind: ActionKind
    public var title: String = ""
    public var x: Double = 0
    public var y: Double = 0
    public var button: MouseButton = .left
    public var clickCount: Int = 1
    public var delayMilliseconds: Double = 0
    public var durationMilliseconds: Double = 300
    public var scrollX: Int32 = 0
    public var scrollY: Int32 = -3
    public var keyCode: UInt16 = 0
    public var modifiers: UInt64 = 0
    public var text: String = ""
    public init(kind: ActionKind) { self.kind = kind }
    public var displayTitle: String { title.isEmpty ? kind.title : title }
    public var summary: String {
        func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
        switch kind {
        case .move: return "X \(number(x)) · Y \(number(y))"
        case .click: return "\(button.title)\(clickCount == 2 ? "双击" : "单击") · \(number(x)), \(number(y))"
        case .mouseDown, .mouseUp: return "\(button.title) · \(number(x)), \(number(y))"
        case .scroll: return "垂直 \(scrollY) · 水平 \(scrollX)"
        case .wait: return "\(number(durationMilliseconds)) ms"
        case .keyPress, .keyDown, .keyUp: return KeyNames.label(keyCode: UInt32(keyCode), modifiers: modifiers)
        case .text: return text.isEmpty ? "尚未输入文本" : String(text.prefix(32))
        }
    }
}

public struct MouseScript: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var steps: [ScriptStep] = []
    public var loopCount: Int = 1
    public var speed: Double = 1
    public init(name: String = "未命名脚本") { self.name = name }
    public var enabledSteps: [ScriptStep] { steps.filter(\.enabled) }
    public var estimatedMilliseconds: Double {
        enabledSteps.reduce(0) { $0 + $1.delayMilliseconds + ($1.kind == .wait ? $1.durationMilliseconds : 0) } / max(0.25, speed)
    }
    public mutating func duplicateIdentity() {
        id = UUID(); createdAt = Date(); updatedAt = Date()
        for index in steps.indices { steps[index].id = UUID() }
    }
}

public struct ClickConfiguration: Codable, Equatable, Sendable {
    public var intervalMilliseconds: Double = 1000
    public var button: MouseButton = .left
    public var clickCount: Int = 1
    public var repeatCount: Int = 10
    public var startDelay: Double = 3
    public var useFixedPosition: Bool = false
    public var x: Double = 0
    public var y: Double = 0
    public init() {}
    public func validate() throws {
        guard intervalMilliseconds.isFinite, (50...3_600_000).contains(intervalMilliseconds) else { throw ValidationError.invalid("点击间隔应在 50–3,600,000 ms 之间。") }
        guard (0...1_000_000).contains(repeatCount), (1...2).contains(clickCount), startDelay.isFinite, (0...60).contains(startDelay), x.isFinite, y.isFinite, abs(x) <= 100_000, abs(y) <= 100_000 else { throw ValidationError.invalid("点击次数、启动延迟或坐标超出范围。") }
    }
}

public enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String { switch self { case .system: "跟随系统"; case .light: "浅色"; case .dark: "深色" } }
}

public enum HotkeyAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case runPause, record, stop, pick
    public var id: String { rawValue }
    public var title: String { switch self { case .runPause: "启动 / 暂停 / 继续"; case .record: "开始 / 结束录制"; case .stop: "立即停止"; case .pick: "拾取鼠标坐标" } }
    public var defaultBinding: HotkeyBinding {
        let code: UInt32 = switch self { case .runPause: 36; case .record: 15; case .stop: 1; case .pick: 35 }
        return HotkeyBinding(keyCode: code, modifiers: 0x100 | 0x800)
    }
}

public struct HotkeyBinding: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    // Carbon modifier bits, deliberately separate from CGEventFlags.
    public var modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    public var label: String {
        (modifiers & 0x100 != 0 ? "⌘" : "") + (modifiers & 0x1000 != 0 ? "⌃" : "") + (modifiers & 0x800 != 0 ? "⌥" : "") + (modifiers & 0x200 != 0 ? "⇧" : "") + KeyNames.name(keyCode)
    }
}

public enum KeyNames {
    public static let options: [(code: UInt32, name: String)] = [(36,"↩"),(49,"空格"),(0,"A"),(11,"B"),(8,"C"),(2,"D"),(14,"E"),(3,"F"),(5,"G"),(4,"H"),(34,"I"),(38,"J"),(40,"K"),(37,"L"),(46,"M"),(45,"N"),(31,"O"),(35,"P"),(12,"Q"),(15,"R"),(1,"S"),(17,"T"),(32,"U"),(9,"V"),(13,"W"),(7,"X"),(16,"Y"),(6,"Z"),(18,"1"),(19,"2"),(20,"3"),(21,"4"),(23,"5"),(22,"6"),(26,"7"),(28,"8"),(25,"9"),(29,"0"),(53,"Esc"),(48,"Tab"),(51,"⌫"),(123,"←"),(124,"→"),(125,"↓"),(126,"↑"),(122,"F1"),(120,"F2"),(99,"F3"),(118,"F4"),(96,"F5"),(97,"F6"),(98,"F7"),(100,"F8"),(101,"F9"),(109,"F10"),(103,"F11"),(111,"F12")]
    public static func name(_ code: UInt32) -> String { options.first { $0.code == code }?.name ?? "键码 \(code)" }
    public static func label(keyCode: UInt32, modifiers: UInt64) -> String {
        (modifiers & (1 << 20) != 0 ? "⌘" : "") + (modifiers & (1 << 18) != 0 ? "⌃" : "") + (modifiers & (1 << 19) != 0 ? "⌥" : "") + (modifiers & (1 << 17) != 0 ? "⇧" : "") + name(keyCode)
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var theme: AppTheme = .system
    public var cornerFailsafe: Bool = true
    public var recordMouseMovement: Bool = true
    public var recordKeyboard: Bool = false
    public var launchDelay: Double = 3
    public var hotkeys: [HotkeyAction: HotkeyBinding] = Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, $0.defaultBinding) })
    public init() {}
}

public struct Workspace: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var scripts: [MouseScript] = []
    public var selectedScriptID: UUID?
    public var clickConfiguration = ClickConfiguration()
    public var preferences = AppPreferences()
    public init() {}
    public func validate() throws {
        guard schemaVersion == 1 else { throw ValidationError.invalid("此文件来自不支持的版本。") }
        guard scripts.count <= 500, Set(scripts.map(\.id)).count == scripts.count else { throw ValidationError.invalid("脚本数量过多或标识重复。") }
        try clickConfiguration.validate()
        guard preferences.launchDelay.isFinite, (0...60).contains(preferences.launchDelay), preferences.hotkeys.count == HotkeyAction.allCases.count, Set(preferences.hotkeys.values).count == HotkeyAction.allCases.count else { throw ValidationError.invalid("快捷键重复、缺失或启动延迟无效。") }
        for binding in preferences.hotkeys.values {
            guard binding.keyCode <= 126, binding.modifiers & (0x100 | 0x1000 | 0x800) != 0, binding.modifiers & ~UInt32(0x100 | 0x200 | 0x800 | 0x1000) == 0 else { throw ValidationError.invalid("全局快捷键至少需要 Command、Control 或 Option 修饰键。") }
        }
        for script in scripts { try script.validate() }
    }
}

public enum ValidationError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

extension MouseScript {
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120 else { throw ValidationError.invalid("脚本名需要 1–120 个字符。") }
        guard (0...100_000).contains(loopCount), speed.isFinite, (0.25...4).contains(speed), steps.count <= 10_000, Set(steps.map(\.id)).count == steps.count else { throw ValidationError.invalid("脚本循环、速度或步骤数量无效。") }
        for step in steps {
            guard step.x.isFinite, step.y.isFinite, abs(step.x) <= 100_000, abs(step.y) <= 100_000, step.delayMilliseconds.isFinite, (0...3_600_000).contains(step.delayMilliseconds), step.durationMilliseconds.isFinite, (0...3_600_000).contains(step.durationMilliseconds), (1...2).contains(step.clickCount), step.keyCode <= 126, step.text.utf16.count <= 10_000, abs(Int64(step.scrollX)) <= 10_000, abs(Int64(step.scrollY)) <= 10_000 else { throw ValidationError.invalid("步骤「\(step.displayTitle)」含有超出范围的参数。") }
        }
    }
}
