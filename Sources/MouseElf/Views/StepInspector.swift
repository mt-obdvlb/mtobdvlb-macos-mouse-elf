import SwiftUI
import MouseElfCore

struct StepInspector: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("步骤检查器").font(.headline); Spacer(); Image(systemName: "sidebar.right").foregroundStyle(.secondary) }.padding(16)
            Divider()
            if let step = store.selectedStep {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Label(step.kind.title, systemImage: step.kind.systemImage).font(.title3).fontWeight(.semibold)
                        VStack(alignment: .leading, spacing: 6) {
                            caption("步骤备注")
                            TextField("可选，方便识别这一步", text: binding(\.title, fallback: ""))
                                .accessibilityIdentifier("stepTitle")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            caption("动作类型")
                            Picker("动作类型", selection: binding(\.kind, fallback: .click)) {
                                ForEach(ActionKind.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden().accessibilityIdentifier("stepKind")
                        }
                        Divider()
                        parameters(step)
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            caption("执行前等待 · ms")
                            TextField("等待毫秒数", value: binding(\.delayMilliseconds, fallback: 0), format: .number)
                                .accessibilityIdentifier("stepDelay")
                            Text("相对于上一个动作完成的间隔。").font(.caption2).foregroundStyle(.secondary)
                        }
                        Toggle("启用此步骤", isOn: binding(\.enabled, fallback: true)).toggleStyle(.checkbox)
                        HStack(spacing: 8) {
                            Button { store.moveStep(step.id, by: -1) } label: { Image(systemName: "arrow.up") }.help("上移步骤").accessibilityLabel("上移步骤").accessibilityIdentifier("moveStepUp")
                            Button { store.moveStep(step.id, by: 1) } label: { Image(systemName: "arrow.down") }.help("下移步骤").accessibilityLabel("下移步骤").accessibilityIdentifier("moveStepDown")
                            Button { store.duplicateStep(step.id) } label: { Image(systemName: "doc.on.doc") }.help("复制步骤").accessibilityLabel("复制步骤").accessibilityIdentifier("duplicateStep")
                            Spacer()
                            Button(role: .destructive) { store.deleteStep(step.id) } label: { Image(systemName: "trash") }.help("删除步骤").accessibilityLabel("删除步骤").accessibilityIdentifier("deleteStep")
                        }
                    }.padding(18).textFieldStyle(.roundedBorder).disabled(!store.canEdit)
                }
            } else {
                EmptyWorkspace(title: "选择一个步骤", description: "在时间线中选择动作，即可查看和调整详细参数。", image: "slider.horizontal.3")
            }
        }.frame(maxHeight: .infinity).background(.quaternary.opacity(0.15))
    }

    @ViewBuilder private func parameters(_ step: ScriptStep) -> some View {
        if step.kind.usesPosition {
            VStack(alignment: .leading, spacing: 8) {
                caption("屏幕坐标")
                HStack { Text("X").foregroundStyle(.secondary); TextField("X 坐标", value: binding(\.x, fallback: 0), format: .number).accessibilityIdentifier("stepX") }
                HStack { Text("Y").foregroundStyle(.secondary); TextField("Y 坐标", value: binding(\.y, fallback: 0), format: .number).accessibilityIdentifier("stepY") }
                Button { store.pickPosition() } label: { Label("拾取坐标", systemImage: "eyedropper") }.accessibilityIdentifier("pickStepPosition")
            }
        }
        if [.click, .mouseDown, .mouseUp].contains(step.kind) {
            VStack(alignment: .leading, spacing: 8) {
                caption("鼠标按键")
                Picker("鼠标按键", selection: binding(\.button, fallback: .left)) {
                    ForEach(MouseButton.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.segmented)
                if step.kind == .click {
                    Picker("点击次数", selection: binding(\.clickCount, fallback: 1)) { Text("单击").tag(1); Text("双击").tag(2) }.pickerStyle(.segmented).labelsHidden()
                }
            }
        }
        if step.kind == .scroll {
            VStack(alignment: .leading, spacing: 8) {
                caption("滚动距离 · 行")
                LabeledContent("垂直") { TextField("垂直滚动", value: binding(\.scrollY, fallback: -3), format: .number) }
                LabeledContent("水平") { TextField("水平滚动", value: binding(\.scrollX, fallback: 0), format: .number) }
                Text("垂直负数向下，正数向上。").font(.caption2).foregroundStyle(.secondary)
            }
        }
        if step.kind == .wait {
            VStack(alignment: .leading, spacing: 8) {
                caption("等待时长 · ms")
                TextField("等待时长", value: binding(\.durationMilliseconds, fallback: 300), format: .number).accessibilityIdentifier("stepDuration")
            }
        }
        if step.kind.usesKey {
            VStack(alignment: .leading, spacing: 8) {
                caption("按键")
                Picker("按键", selection: binding(\.keyCode, fallback: 0)) {
                    ForEach(KeyNames.options, id: \.code) { Text($0.name).tag(UInt16($0.code)) }
                }.labelsHidden().accessibilityIdentifier("stepKey")
                caption("修饰键")
                HStack(spacing: 6) {
                    modifier("⌘", bit: 1 << 20)
                    modifier("⌃", bit: 1 << 18)
                    modifier("⌥", bit: 1 << 19)
                    modifier("⇧", bit: 1 << 17)
                }
            }
        }
        if step.kind == .text {
            VStack(alignment: .leading, spacing: 8) {
                caption("输入文本")
                TextEditor(text: binding(\.text, fallback: "")).font(.body)
                    .frame(minHeight: 120).padding(5).background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .accessibilityIdentifier("stepText")
                Text("直接输入 Unicode 文本，不会覆盖剪贴板。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func caption(_ title: String) -> some View { Text(title).font(.caption).foregroundStyle(.secondary) }
    private func modifier(_ title: String, bit: UInt64) -> some View {
        Toggle(title, isOn: Binding(get: { (store.selectedStep?.modifiers ?? 0) & bit != 0 }, set: { value in
            guard var step = store.selectedStep else { return }
            if value { step.modifiers |= bit } else { step.modifiers &= ~bit }
            store.updateStep(step)
        })).toggleStyle(.button).help("\(title) 修饰键")
    }
    private func binding<Value>(_ path: WritableKeyPath<ScriptStep, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { store.selectedStep?[keyPath: path] ?? fallback }, set: { value in
            guard var step = store.selectedStep else { return }
            step[keyPath: path] = value; store.updateStep(step)
        })
    }
}
