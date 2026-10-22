import SwiftUI
import MouseElfCore

struct TasksView: View {
    @Bindable var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeading(title: "让重复点击，自动完成。", subtitle: "配置点击规则，然后把时间留给更重要的事。")
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 18) {
                        clickRules
                        positionRules
                    }.frame(maxWidth: .infinity)
                    runPanel.frame(width: 260)
                }
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb").foregroundStyle(.teal)
                    Text(store.workspace.preferences.cornerFailsafe ? "运行时可切换到其他应用。使用全局快捷键暂停或停止；将鼠标移至任意屏幕角落也可紧急停止。" : "运行时可切换到其他应用，使用全局快捷键暂停或停止。角落紧急停止当前已关闭。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28)
        }
        .background(.quaternary.opacity(0.2))
    }

    private var clickRules: some View {
        Panel(title: "点击规则", systemImage: "cursorarrow.click") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 18) {
                GridRow {
                    FieldCaption(title: "点击间隔", detail: "最小 50 ms")
                    HStack { TextField("间隔", value: $store.workspace.clickConfiguration.intervalMilliseconds, format: .number).accessibilityIdentifier("clickInterval"); Text("ms").foregroundStyle(.secondary) }
                }
                GridRow {
                    Text("鼠标按键")
                    Picker("鼠标按键", selection: $store.workspace.clickConfiguration.button) {
                        ForEach(MouseButton.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().pickerStyle(.segmented)
                }
                GridRow {
                    Text("点击方式")
                    Picker("点击方式", selection: $store.workspace.clickConfiguration.clickCount) {
                        Text("单击").tag(1); Text("双击").tag(2)
                    }.labelsHidden().pickerStyle(.segmented)
                }
                GridRow {
                    FieldCaption(title: "执行次数", detail: "设为 0 时持续运行")
                    TextField("次数", value: $store.workspace.clickConfiguration.repeatCount, format: .number).accessibilityIdentifier("clickRepeatCount")
                }
                GridRow {
                    FieldCaption(title: "启动倒计时", detail: "预留时间切换应用")
                    HStack { TextField("倒计时", value: $store.workspace.clickConfiguration.startDelay, format: .number); Text("秒").foregroundStyle(.secondary) }
                }
            }.textFieldStyle(.roundedBorder).disabled(!store.canEdit)
        }
    }

    private var positionRules: some View {
        Panel(title: "点击位置", systemImage: "scope") {
            Picker("点击位置", selection: $store.workspace.clickConfiguration.useFixedPosition) {
                Text("跟随当前鼠标").tag(false)
                Text("固定坐标").tag(true)
            }.pickerStyle(.segmented).labelsHidden().disabled(!store.canEdit)
            if store.workspace.clickConfiguration.useFixedPosition {
                HStack(spacing: 12) {
                    Text("X").foregroundStyle(.secondary)
                    TextField("X 坐标", value: $store.workspace.clickConfiguration.x, format: .number)
                        .accessibilityIdentifier("clickPositionX")
                    Text("Y").foregroundStyle(.secondary)
                    TextField("Y 坐标", value: $store.workspace.clickConfiguration.y, format: .number)
                        .accessibilityIdentifier("clickPositionY")
                    Button { store.pickPosition() } label: { Label("拾取", systemImage: "eyedropper") }
                        .accessibilityIdentifier("pickPosition").help("读取当前鼠标坐标；在其他应用中可使用全局快捷键拾取")
                }.textFieldStyle(.roundedBorder).disabled(!store.canEdit)
                Text("使用 \(store.hotkeyLabel(.pick)) 拾取目标坐标；支持多显示器坐标。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("每次点击发生在鼠标当时的位置，可在运行中移动鼠标。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var runPanel: some View {
        Panel(title: "运行控制", systemImage: "play.circle") {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    StatusDot(active: store.engine.isActive)
                    Text(store.engine.status).font(.callout).foregroundStyle(.secondary)
                }.accessibilityIdentifier("engineStatus")
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(store.engine.completedActions)").font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit()
                    Text("已完成动作").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                LabeledContent("目标次数", value: store.workspace.clickConfiguration.repeatCount == 0 ? "持续执行" : "\(store.workspace.clickConfiguration.repeatCount) 次").font(.callout)
                LabeledContent("点击间隔", value: durationLabel(store.workspace.clickConfiguration.intervalMilliseconds)).font(.callout)
                if !store.engine.isActive {
                    Button { store.startClicking() } label: {
                        Label("开始点击", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(store.recorder.isRecording).accessibilityIdentifier("startClicking")
                } else {
                    RunControls(store: store)
                }
                HStack { Text("启动 / 暂停").font(.caption).foregroundStyle(.secondary); Spacer(); ShortcutBadge(text: store.hotkeyLabel(.runPause)) }
                if !store.permissions.accessibilityGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("需要辅助功能权限", systemImage: "lock.shield").font(.caption).foregroundStyle(.orange)
                        Button("前往授权") { store.section = .settings }.accessibilityIdentifier("taskPermissionSettings")
                    }
                }
                if let error = store.engine.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
    }
}
