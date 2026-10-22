import SwiftUI
import MouseElfCore

struct SettingsView: View {
    @Bindable var store: AppStore
    @State private var draftHotkeys = AppPreferences().hotkeys
    private var hotkeysChanged: Bool { draftHotkeys != store.workspace.preferences.hotkeys }
    private var hotkeyConfigurationValid: Bool {
        let bindings = HotkeyAction.allCases.compactMap { draftHotkeys[$0] }
        return bindings.count == 4 && Set(bindings).count == 4 && bindings.allSatisfy { $0.modifiers & (0x100 | 0x1000 | 0x800) != 0 }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "按你的习惯工作。", subtitle: "权限、全局快捷键与安全选项，都在这里。")
                permissionsPanel
                behaviorPanel
                hotkeysPanel
                logsPanel
                HStack {
                    Label(store.hasUnsavedChanges ? "正在保存工作区…" : "工作区已保存至本机", systemImage: "internaldrive")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("打开数据目录") { store.openDataDirectory() }.accessibilityIdentifier("openDataDirectory")
                    Button("立即保存") { store.save() }
                }
                if let error = store.lastSaveError {
                    Label("尚未保存：\(error)", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
            }.padding(28)
        }.background(.quaternary.opacity(0.2))
        .onAppear { draftHotkeys = store.workspace.preferences.hotkeys }
    }

    private var permissionsPanel: some View {
        Panel(title: "系统权限", systemImage: "lock.shield") {
            permissionRow(title: "辅助功能", description: "用于发送鼠标点击、滚动和键盘动作。", granted: store.permissions.accessibilityGranted, request: store.permissions.requestAccessibility, settings: store.permissions.openAccessibilitySettings, identifier: "accessibility")
            Divider()
            permissionRow(title: "输入监控", description: "用于在其他应用中录制全局鼠标和可选键盘事件。", granted: store.permissions.inputMonitoringGranted, request: store.permissions.requestInputMonitoring, settings: store.permissions.openInputMonitoringSettings, identifier: "inputMonitoring")
            HStack {
                Text("修改系统授权后可刷新状态。若系统要求，请退出并重新打开鼠标精灵。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { store.permissions.refresh() } label: { Label("刷新状态", systemImage: "arrow.clockwise") }.accessibilityIdentifier("refreshPermissions")
            }
        }
    }

    private func permissionRow(title: String, description: String, granted: Bool, request: @escaping () -> Void, settings: @escaping () -> Void, identifier: String) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title).fontWeight(.medium)
                    Label(granted ? "已授权" : "未授权", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.caption).foregroundStyle(granted ? Color.teal : Color.orange)
                }
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("请求授权", action: request).accessibilityIdentifier("request_\(identifier)") }
            Button("系统设置", action: settings).accessibilityIdentifier("settings_\(identifier)")
        }
    }

    private var behaviorPanel: some View {
        Panel(title: "通用偏好", systemImage: "slider.horizontal.3") {
            Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 18) {
                GridRow {
                    Text("外观")
                    Picker("外观", selection: $store.workspace.preferences.theme) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 340).accessibilityIdentifier("themePicker")
                }
                GridRow {
                    FieldCaption(title: "角落紧急停止", detail: "运行时将鼠标移至任意屏幕角落")
                    Toggle("角落紧急停止", isOn: $store.workspace.preferences.cornerFailsafe).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("cornerFailsafe")
                }
                GridRow {
                    FieldCaption(title: "录制鼠标移动", detail: "关闭时省略空闲移动，仍保留点击、拖拽和滚动")
                    Toggle("录制鼠标移动", isOn: $store.workspace.preferences.recordMouseMovement).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("recordMouseMovement")
                }
                GridRow {
                    FieldCaption(title: "录制键盘", detail: "默认关闭；启用后会记录键盘操作，请避开敏感输入")
                    Toggle("录制键盘", isOn: $store.workspace.preferences.recordKeyboard).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("recordKeyboard")
                }
                GridRow {
                    FieldCaption(title: "脚本回放倒计时", detail: "开始前预留时间切换到目标应用")
                    HStack { TextField("回放倒计时", value: $store.workspace.preferences.launchDelay, format: .number).frame(width: 70).textFieldStyle(.roundedBorder).accessibilityIdentifier("playbackCountdown"); Text("秒").foregroundStyle(.secondary) }
                }
            }.disabled(!store.canEdit)
        }
    }

    private var hotkeysPanel: some View {
        Panel(title: "全局快捷键", systemImage: "command") {
            Text("在任何应用中都能控制鼠标精灵。快捷键至少包含 ⌘、⌃ 或 ⌥，修改后点击“应用快捷键”生效。")
                .font(.callout).foregroundStyle(.secondary)
            VStack(spacing: 14) {
                ForEach(HotkeyAction.allCases) { action in
                    HotkeyEditor(store: store, bindings: $draftHotkeys, action: action)
                    if action != .pick { Divider() }
                }
            }.disabled(!store.canEdit)
            if !hotkeyConfigurationValid {
                Label("快捷键不能重复，且至少需要 Command、Control 或 Option。", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).accessibilityIdentifier("hotkeyValidationError")
            }
            HStack {
                Text(hotkeysChanged ? "有待应用的修改" : "使用系统级全局快捷键")
                    .font(.caption).foregroundStyle(hotkeysChanged ? Color.orange : Color.secondary)
                Spacer()
                Button("恢复默认") { store.restoreHotkeys(); draftHotkeys = store.workspace.preferences.hotkeys }.disabled(!store.canEdit).accessibilityIdentifier("restoreHotkeys")
                Button("应用快捷键") { store.workspace.preferences.hotkeys = draftHotkeys; store.applyHotkeys() }
                    .buttonStyle(.borderedProminent).disabled(!store.canEdit || !hotkeyConfigurationValid).accessibilityIdentifier("applyHotkeys")
            }
        }
    }

    private var logsPanel: some View {
        Panel(title: "运行日志", systemImage: "text.alignleft") {
            if store.logs.isEmpty {
                Text("暂无运行记录。启动任务或录制后，操作结果会显示在这里。")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.logs.prefix(15)) { entry in
                        HStack(alignment: .top, spacing: 14) {
                            Text(entry.date, format: .dateTime.hour().minute().second()).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                            Text(entry.message).font(.caption).textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                    }
                }.accessibilityIdentifier("activityLogs")
            }
            HStack { Spacer(); Button("清空日志") { store.clearLogs() }.disabled(store.logs.isEmpty) }
        }
    }
}

private struct HotkeyEditor: View {
    @Bindable var store: AppStore
    @Binding var bindings: [HotkeyAction: HotkeyBinding]
    let action: HotkeyAction
    private var binding: HotkeyBinding { bindings[action] ?? action.defaultBinding }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(action.title).frame(maxWidth: .infinity, alignment: .leading)
                modifier("⌘", bit: 0x100)
                modifier("⌃", bit: 0x1000)
                modifier("⌥", bit: 0x800)
                modifier("⇧", bit: 0x200)
                Picker("\(action.title)按键", selection: Binding(get: { binding.keyCode }, set: { value in
                    var edited = binding; edited.keyCode = value; bindings[action] = edited
                })) {
                    ForEach(KeyNames.options, id: \.code) { Text($0.name).tag($0.code) }
                }.labelsHidden().frame(width: 88).accessibilityIdentifier("hotkey_\(action.rawValue)")
                ShortcutBadge(text: binding.label).frame(width: 76, alignment: .trailing)
            }
            if let error = store.hotkeyErrors[action] {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }
    private func modifier(_ title: String, bit: UInt32) -> some View {
        Toggle(title, isOn: Binding(get: { binding.modifiers & bit != 0 }, set: { value in
            var edited = binding
            if value { edited.modifiers |= bit } else { edited.modifiers &= ~bit }
            bindings[action] = edited
        })).toggleStyle(.button).help("\(action.title)：\(title) 修饰键")
    }
}
