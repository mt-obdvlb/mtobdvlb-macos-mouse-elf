import SwiftUI
import MouseElfCore

struct RecordingView: View {
    @Bindable var store: AppStore
    private var visibleSteps: [ScriptStep] { store.recorder.isRecording ? store.recorder.steps : store.selectedScript?.steps ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    PageHeading(title: "把操作，变成可编辑的流程。", subtitle: "录下鼠标与键盘动作，逐步调整，再一键回放。")
                    Spacer()
                    Button { store.newScript() } label: { Label("新建脚本", systemImage: "plus") }
                        .disabled(!store.canEdit).accessibilityIdentifier("newRecordingScript")
                }
                recordingControls
                if store.recorder.isRecording {
                    Text("切换到目标应用开始操作。按 Esc 或录制快捷键结束；应用自身的操作会被忽略。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.selectedScript != nil { scriptConfiguration }
            }.padding(24)
            Divider()
            if store.selectedScript != nil || store.recorder.isRecording {
                HSplitView {
                    VStack(spacing: 0) {
                        timelineToolbar
                        Divider()
                        if visibleSteps.isEmpty {
                            EmptyWorkspace(title: "你的流程从这里开始", description: "点击“开始录制”捕捉真实操作，或用“添加步骤”手动编排。", image: "point.topleft.down.to.point.bottomright.curvepath")
                        } else {
                            List {
                                ForEach(Array(visibleSteps.enumerated()), id: \.element.id) { index, step in
                                    StepRow(store: store, step: step, index: index)
                                        .listRowBackground(store.selectedStepID == step.id ? Color.teal.opacity(0.1) : Color.clear)
                                }
                            }.listStyle(.inset).accessibilityIdentifier("stepsList")
                        }
                        Divider()
                        HStack {
                            Text("\(visibleSteps.count) 个步骤").font(.caption)
                            Spacer()
                            if store.recorder.isRecording { Text(String(format: "已录制 %.1f 秒", store.recorder.elapsed)).monospacedDigit().font(.caption).foregroundStyle(.red) }
                            else if let script = store.selectedScript { Text("单轮约 \(durationLabel(script.estimatedMilliseconds))").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.horizontal, 16).padding(.vertical, 9)
                    }.frame(minWidth: 400, maxWidth: .infinity)
                    StepInspector(store: store).frame(minWidth: 265, idealWidth: 285, maxWidth: 340)
                }
            } else {
                EmptyWorkspace(title: "创建你的第一个脚本", description: "从录制真实操作开始，或新建一个脚本手动添加动作。", image: "record.circle")
            }
        }
    }

    private var recordingControls: some View {
        HStack(spacing: 12) {
            Button { store.toggleRecording() } label: {
                Label(store.recorder.isRecording ? "结束录制" : "开始录制", systemImage: store.recorder.isRecording ? "stop.circle.fill" : "record.circle")
            }.buttonStyle(.borderedProminent).tint(store.recorder.isRecording ? .red : .teal)
                .controlSize(.large).disabled(store.engine.isActive)
                .accessibilityIdentifier("toggleRecording")
            ShortcutBadge(text: store.hotkeyLabel(.record))
            Divider().frame(height: 24)
            if !store.engine.isActive {
                Button { store.togglePlayback() } label: { Label("回放脚本", systemImage: "play.fill") }
                    .controlSize(.large).disabled(store.recorder.isRecording || (store.selectedScript?.enabledSteps.isEmpty ?? true))
                    .accessibilityIdentifier("playScript")
            } else {
                RunControls(store: store)
                Text(store.engine.status).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if store.recorder.isRecording {
                Label("录制中", systemImage: "circle.fill").font(.caption).foregroundStyle(.red)
            } else if !store.permissions.inputMonitoringGranted || !store.permissions.accessibilityGranted {
                Button { store.section = .settings } label: { Label("检查录制权限", systemImage: "lock.shield") }
                    .accessibilityIdentifier("recordingPermissionSettings")
            }
        }
    }

    private var scriptConfiguration: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("脚本名称").font(.caption).foregroundStyle(.secondary)
                TextField("脚本名称", text: binding(\.name, fallback: ""))
                    .accessibilityIdentifier("scriptName")
            }.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 5) {
                Text("循环次数 · 0 为持续").font(.caption).foregroundStyle(.secondary)
                TextField("循环次数", value: binding(\.loopCount, fallback: 1), format: .number)
                    .accessibilityIdentifier("scriptLoopCount")
            }.frame(width: 125)
            VStack(alignment: .leading, spacing: 5) {
                Text("回放速度").font(.caption).foregroundStyle(.secondary)
                Picker("回放速度", selection: binding(\.speed, fallback: 1)) {
                    Text("0.25×").tag(0.25); Text("0.5×").tag(0.5); Text("1×").tag(1.0); Text("1.5×").tag(1.5); Text("2×").tag(2.0); Text("4×").tag(4.0)
                }.labelsHidden().accessibilityIdentifier("scriptSpeed")
            }.frame(width: 95)
        }.textFieldStyle(.roundedBorder).disabled(!store.canEdit)
    }

    private var timelineToolbar: some View {
        HStack {
            Label("操作时间线", systemImage: "list.bullet.indent").font(.headline)
            Spacer()
            Menu {
                ForEach(ActionKind.allCases) { kind in
                    Button { store.addStep(kind) } label: { Label(kind.title, systemImage: kind.systemImage) }
                }
            } label: { Label("添加步骤", systemImage: "plus") }
                .fixedSize().disabled(!store.canEdit).accessibilityIdentifier("addStep")
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func binding<Value>(_ path: WritableKeyPath<MouseScript, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { store.selectedScript?[keyPath: path] ?? fallback }, set: { value in
            guard var script = store.selectedScript else { return }
            script[keyPath: path] = value
            store.updateScript(script)
        })
    }
}

private struct StepRow: View {
    @Bindable var store: AppStore
    let step: ScriptStep
    let index: Int
    var body: some View {
        HStack(spacing: 12) {
            Toggle("启用步骤 \(index + 1)", isOn: Binding(get: { step.enabled }, set: { value in
                var edited = step; edited.enabled = value; store.updateStep(edited)
            })).labelsHidden().toggleStyle(.checkbox).disabled(!store.canEdit)
            Button { store.selectedStepID = step.id } label: {
                HStack(spacing: 12) {
                    Text(String(format: "%02d", index + 1)).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 24)
                    Image(systemName: step.kind.systemImage).font(.system(size: 16)).foregroundStyle(store.engine.activeStepID == step.id ? Color.teal : Color.secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.displayTitle).font(.body).foregroundStyle(step.enabled ? .primary : .secondary)
                        Text(step.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if step.delayMilliseconds > 0 { Text("+\(durationLabel(step.delayMilliseconds))").font(.caption2).foregroundStyle(.tertiary) }
                    if store.engine.activeStepID == step.id { Image(systemName: "play.fill").font(.caption).foregroundStyle(.teal) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("步骤 \(index + 1)，\(step.displayTitle)，\(step.summary)")
                .accessibilityIdentifier("step_\(index)")
        }.padding(.vertical, 7)
        .contextMenu {
            Group {
                Button("复制步骤") { store.duplicateStep(step.id) }
                Button("上移") { store.moveStep(step.id, by: -1) }.disabled(index == 0)
                Button("下移") { store.moveStep(step.id, by: 1) }
                Divider()
                Button("删除步骤", role: .destructive) { store.deleteStep(step.id) }
            }.disabled(!store.canEdit)
        }.disabled(store.recorder.isRecording)
    }
}
