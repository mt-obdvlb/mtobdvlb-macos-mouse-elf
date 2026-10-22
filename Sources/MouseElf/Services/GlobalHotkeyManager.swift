import Carbon
import MouseElfCore

@MainActor
final class GlobalHotkeyManager {
    private var registrations: [HotkeyAction: EventHotKeyRef] = [:]
    private var actionIDs: [UInt32: HotkeyAction] = [:]
    private var pressedIDs = Set<UInt32>()
    private var eventHandler: EventHandlerRef?
    private var handler: ((HotkeyAction) -> Void)?
    private let signature: OSType = 0x4D45_4C46

    /// Returns a per-action error, so the UI never claims an unavailable shortcut is active.
    func register(_ bindings: [HotkeyAction: HotkeyBinding], handler: @escaping (HotkeyAction) -> Void) -> [HotkeyAction: String] {
        unregisterAll()
        self.handler = handler
        var errors: [HotkeyAction: String] = [:]
        let specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, numericCast(MemoryLayout<EventHotKeyID>.size), nil, &identifier)
            guard result == noErr else { return result }
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated {
                guard identifier.signature == manager.signature, let action = manager.actionIDs[identifier.id] else { return OSStatus(eventNotHandledErr) }
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { manager.pressedIDs.remove(identifier.id) }
                else if manager.pressedIDs.insert(identifier.id).inserted { manager.handler?(action) }
                return noErr
            }
        }
        let installed = specs.withUnsafeBufferPointer {
            InstallEventHandler(GetApplicationEventTarget(), callback, numericCast(specs.count), $0.baseAddress, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
        guard installed == noErr else {
            for action in HotkeyAction.allCases { errors[action] = "无法安装系统快捷键处理器（\(installed)）。" }
            return errors
        }

        var seen = Set<HotkeyBinding>()
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let binding = bindings[action] else { errors[action] = "尚未配置快捷键。"; continue }
            guard binding.keyCode <= 126, binding.modifiers & (0x100 | 0x800 | 0x1000) != 0,
                  binding.modifiers & ~UInt32(0x100 | 0x200 | 0x800 | 0x1000) == 0 else {
                errors[action] = "请设置带 Command、Option 或 Control 的有效快捷键。"; continue
            }
            guard seen.insert(binding).inserted else { errors[action] = "与其它功能的快捷键重复。"; continue }
            let id = UInt32(index + 1)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), numericCast(kEventHotKeyExclusive), &reference)
            if status == noErr, let reference {
                registrations[action] = reference; actionIDs[id] = action
            } else {
                errors[action] = status == OSStatus(eventHotKeyExistsErr) ? "该快捷键已被系统或其它应用占用，请更换组合。" : "注册失败（\(status)），此快捷键当前不可用。"
            }
        }
        return errors
    }

    func unregisterAll() {
        for reference in registrations.values { UnregisterEventHotKey(reference) }
        registrations.removeAll(); actionIDs.removeAll(); pressedIDs.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil; handler = nil
    }
}
