import AppKit
import ApplicationServices
import Observation

@MainActor @Observable
final class PermissionService {
    private(set) var accessibilityGranted = false
    private(set) var inputMonitoringGranted = false

    init() { refresh() }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    func requestInputMonitoring() {
        inputMonitoringGranted = CGRequestListenEventAccess()
    }

    func openAccessibilitySettings() { openSettings("Privacy_Accessibility") }
    func openInputMonitoringSettings() { openSettings("Privacy_ListenEvent") }

    private func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
