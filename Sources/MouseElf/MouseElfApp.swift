import AppKit
import SwiftUI
import MouseElfCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: AppStore?
    let mainWindow = MainWindowController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store?.shutdown() == false {
            mainWindow.show()
            return .terminateCancel
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // SwiftUI may have released the last window after Cmd-W. Explicitly
        // recreate its scene and suppress AppKit's default reopen handling.
        return !mainWindow.show()
    }
}

@main
struct MouseElfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: AppStore

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--workspace"), arguments.indices.contains(index + 1) {
            _store = State(initialValue: AppStore(repository: WorkspaceRepository(url: URL(fileURLWithPath: arguments[index + 1]))))
        } else { _store = State(initialValue: AppStore()) }
    }

    var body: some Scene {
        WindowGroup("鼠标精灵", id: "main") {
            MainWindowContent(store: store, delegate: delegate)
                .tint(.teal)
                .preferredColorScheme(store.workspace.preferences.theme == .system ? nil : store.workspace.preferences.theme == .dark ? .dark : .light)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .defaultSize(width: 1180, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建脚本") { store.newScript(); delegate.mainWindow.show() }.keyboardShortcut("n").disabled(!store.canEdit)
                Button("导入脚本…", action: store.importScript).keyboardShortcut("o").disabled(!store.canEdit)
                Button("导出脚本…", action: store.exportScript).keyboardShortcut("e", modifiers: [.command, .shift]).disabled(store.selectedScript == nil)
                Button("保存工作区", action: store.save).keyboardShortcut("s")
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { store.section = .settings; delegate.mainWindow.show() }.keyboardShortcut(",")
            }
            CommandGroup(before: .windowList) {
                Button("打开鼠标精灵") { delegate.mainWindow.show() }.keyboardShortcut("0")
            }
            CommandMenu("自动化") {
                Button("启动 / 暂停 / 继续", action: store.runOrPause)
                    .keyboardShortcut(store.workspace.preferences.hotkeys[.runPause]?.menuShortcut)
                Button("开始 / 结束录制", action: store.toggleRecording)
                    .keyboardShortcut(store.workspace.preferences.hotkeys[.record]?.menuShortcut)
                Button("停止全部任务", action: store.stopAll).keyboardShortcut(".")
                Button("全局紧急停止", action: store.stopAll)
                    .keyboardShortcut(store.workspace.preferences.hotkeys[.stop]?.menuShortcut)
                Divider()
                Button("拾取当前坐标", action: store.pickPosition)
                    .keyboardShortcut(store.workspace.preferences.hotkeys[.pick]?.menuShortcut)
            }
            CommandMenu("前往") {
                ForEach(Array(WorkspaceSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.title) { store.section = section; delegate.mainWindow.show() }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }
        }
        MenuBarExtra("鼠标精灵", systemImage: store.engine.isActive ? "cursorarrow.rays" : store.recorder.isRecording ? "record.circle.fill" : "cursorarrow.click") {
            MenuBarContent(store: store, mainWindow: delegate.mainWindow)
        }
    }
}

private struct MainWindowContent: View {
    let store: AppStore
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RootView(store: store)
            .background(MainWindowRegistration(controller: delegate.mainWindow))
            .onAppear {
                delegate.store = store
                delegate.mainWindow.openNewWindow = { [openWindow] in openWindow(id: "main") }
            }
    }
}

private struct MenuBarContent: View {
    let store: AppStore
    let mainWindow: MainWindowController
    var body: some View {
        Text(store.recorder.isRecording ? "正在录制" : store.engine.status)
        Button("打开鼠标精灵") { mainWindow.show() }
        Divider()
        Button("\(store.engine.isActive ? "暂停 / 继续" : "启动连点")  \(store.hotkeyLabel(.runPause))", action: store.startClicking)
        Button("\(store.recorder.isRecording ? "结束录制" : "开始录制")  \(store.hotkeyLabel(.record))", action: store.toggleRecording)
        Button("立即停止  \(store.hotkeyLabel(.stop))", action: store.stopAll).disabled(!store.engine.isActive && !store.recorder.isRecording)
        Divider()
        Button("退出鼠标精灵") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
