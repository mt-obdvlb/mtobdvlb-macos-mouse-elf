import AppKit
import MouseElfCore
import Observation
import UniformTypeIdentifiers

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case tasks, recording, library, settings
    var id: String { rawValue }
    var title: String { switch self { case .tasks: "任务"; case .recording: "录制"; case .library: "脚本库"; case .settings: "设置" } }
    var systemImage: String { switch self { case .tasks: "cursorarrow.click.2"; case .recording: "record.circle"; case .library: "square.stack.3d.up"; case .settings: "slider.horizontal.3" } }
    var subtitle: String {
        switch self {
        case .tasks: "把重复点击，交给鼠标精灵。"
        case .recording: "记录一次操作，让每一步都可以重来。"
        case .library: "整理你的自动化工作流。"
        case .settings: "让鼠标精灵按你的习惯工作。"
        }
    }
}

struct ActivityEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
}

@MainActor @Observable
final class AppStore {
    var section: WorkspaceSection = .tasks {
        didSet {
            if section == .tasks { runTarget = .clicking }
            else if section == .recording || section == .library { runTarget = .playback }
        }
    }
    var workspace: Workspace { didSet { scheduleSave() } }
    var selectedStepID: UUID?
    var notice: String?
    var errorMessage: String?
    var logs: [ActivityEntry] = []
    var hotkeyErrors: [HotkeyAction: String] = [:]
    private(set) var lastSaveError: String?
    let engine: AutomationEngine
    let recorder: InputRecorder
    let permissions = PermissionService()
    private let hotkeys = GlobalHotkeyManager()
    private let repository: WorkspaceRepository
    private var saveTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var storageBlocked = false
    private var pendingChanges = false
    private let systemIntegration: Bool
    private var runTarget: AutomationMode = .clicking

    init(repository: WorkspaceRepository = .applicationDefault, systemIntegration: Bool = true) {
        self.repository = repository
        self.systemIntegration = systemIntegration
        engine = AutomationEngine()
        recorder = InputRecorder()
        do {
            workspace = try repository.load()
        } catch {
            workspace = Workspace()
            errorMessage = "工作区读取失败，原文件已保留：\(error.localizedDescription)\n\(repository.url.path)"
            storageBlocked = true
        }
        selectedStepID = selectedScript?.steps.first?.id
        engine.onFinish = { [weak self] in
            guard let self else { return }
            self.log(self.engine.error ?? self.engine.status)
            if let error = self.engine.error { self.errorMessage = error }
        }
        recorder.onFinish = { [weak self] in self?.finishRecording() }
        if systemIntegration {
            permissions.refresh()
            applyHotkeys()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.permissions.refresh() }
            }
        }
    }

    var selectedScriptID: UUID? {
        get { workspace.selectedScriptID }
        set { workspace.selectedScriptID = newValue; selectedStepID = selectedScript?.steps.first?.id }
    }
    var selectedScript: MouseScript? { workspace.scripts.first { $0.id == selectedScriptID } }
    var selectedStep: ScriptStep? { selectedScript?.steps.first { $0.id == selectedStepID } }
    var canEdit: Bool { !engine.isActive && !recorder.isRecording }
    var hasUnsavedChanges: Bool { pendingChanges || storageBlocked }

    func startClicking() {
        notice = nil
        guard !recorder.isRecording else { report("请先结束录制，再启动连点任务。"); return }
        if engine.isActive { engine.pauseResume(); return }
        runTarget = .clicking
        do {
            try engine.startClicking(workspace.clickConfiguration, cornerFailsafe: workspace.preferences.cornerFailsafe)
            log("连点任务已启动")
        } catch { report(error.localizedDescription) }
    }

    func togglePlayback() {
        notice = nil
        guard !recorder.isRecording else { report("请先结束录制，再回放脚本。"); return }
        if engine.isActive { engine.pauseResume(); return }
        runTarget = .playback
        guard let script = selectedScript else { report("先创建或打开一个脚本。"); return }
        do {
            try engine.startPlayback(script, startDelay: workspace.preferences.launchDelay, cornerFailsafe: workspace.preferences.cornerFailsafe)
            log("回放脚本「\(script.name)」")
        } catch { report(error.localizedDescription) }
    }

    func toggleRecording() {
        notice = nil
        if recorder.isRecording { finishRecording(); return }
        guard !engine.isActive else { report("请先停止当前任务，再开始录制。"); return }
        guard workspace.scripts.count < 500 else { report("脚本库最多保存 500 个脚本，请先整理脚本库。"); return }
        do {
            try recorder.start(recordMouseMovement: workspace.preferences.recordMouseMovement, recordKeyboard: workspace.preferences.recordKeyboard, hotkeys: workspace.preferences.hotkeys)
            section = .recording
            log("开始录制\(workspace.preferences.recordKeyboard ? "鼠标与键盘" : "鼠标")操作")
        } catch { report(error.localizedDescription) }
    }

    private func finishRecording() {
        let steps = recorder.stop()
        guard !steps.isEmpty else {
            if let error = recorder.error { report(error) } else { notice = "录制已结束，没有记录到操作。请在其他应用中操作鼠标。" }
            return
        }
        var script = MouseScript(name: "录制 · \(Date().formatted(date: .omitted, time: .shortened))")
        script.steps = steps
        workspace.scripts.insert(script, at: 0)
        selectedScriptID = script.id
        section = .recording
        log("录制完成，已保存 \(steps.count) 个步骤")
        notice = "录制完成，已保存 \(steps.count) 个步骤。"
        if let error = recorder.error { report(error) }
        save()
    }

    func stopAll() {
        if recorder.isRecording { finishRecording() }
        if engine.isActive { engine.stop(); log("任务已停止") }
    }

    func pickPosition() {
        let point = CGEvent(source: nil)?.location ?? .zero
        if section == .recording, var step = selectedStep, step.kind.usesPosition {
            guard canEdit else { return }
            step.x = point.x; step.y = point.y
            updateStep(step)
        } else {
            guard canEdit else { return }
            workspace.clickConfiguration.x = point.x
            workspace.clickConfiguration.y = point.y
            workspace.clickConfiguration.useFixedPosition = true
        }
        notice = "已拾取坐标 X \(Int(point.x)) · Y \(Int(point.y))"
    }

    func newScript() {
        notice = nil
        guard canEdit, workspace.scripts.count < 500 else { return }
        let script = MouseScript(name: "新脚本 \(workspace.scripts.count + 1)")
        workspace.scripts.insert(script, at: 0)
        selectedScriptID = script.id
        section = .recording
    }

    func selectScript(_ id: UUID) {
        guard canEdit, workspace.scripts.contains(where: { $0.id == id }) else { return }
        selectedScriptID = id
        section = .recording
    }

    func duplicateScript(_ id: UUID) {
        guard canEdit, workspace.scripts.count < 500, var script = workspace.scripts.first(where: { $0.id == id }) else { return }
        script.duplicateIdentity()
        script.name = String(script.name.prefix(115)) + " 副本"
        workspace.scripts.insert(script, at: 0)
        selectedScriptID = script.id
    }

    func deleteScript(_ id: UUID) {
        guard canEdit else { return }
        workspace.scripts.removeAll { $0.id == id }
        if selectedScriptID == id { selectedScriptID = workspace.scripts.first?.id }
    }

    func updateScript(_ script: MouseScript) {
        guard canEdit, let index = workspace.scripts.firstIndex(where: { $0.id == script.id }) else { return }
        var updated = script; updated.updatedAt = Date()
        workspace.scripts[index] = updated
    }

    func addStep(_ kind: ActionKind) {
        guard canEdit else { return }
        if selectedScript == nil { newScript() }
        guard var script = selectedScript, script.steps.count < 10_000 else { return }
        var step = ScriptStep(kind: kind)
        let point = CGEvent(source: nil)?.location ?? .zero
        step.x = point.x; step.y = point.y
        script.steps.append(step)
        updateScript(script)
        selectedStepID = step.id
    }

    func updateStep(_ step: ScriptStep) {
        guard var script = selectedScript, let index = script.steps.firstIndex(where: { $0.id == step.id }) else { return }
        script.steps[index] = step
        updateScript(script)
    }

    func deleteStep(_ id: UUID) {
        guard var script = selectedScript, let index = script.steps.firstIndex(where: { $0.id == id }) else { return }
        script.steps.remove(at: index)
        updateScript(script)
        if selectedStepID == id { selectedStepID = script.steps.isEmpty ? nil : script.steps[min(index, script.steps.count - 1)].id }
    }

    func duplicateStep(_ id: UUID) {
        guard var script = selectedScript, script.steps.count < 10_000, let index = script.steps.firstIndex(where: { $0.id == id }) else { return }
        var step = script.steps[index]; step.id = UUID()
        script.steps.insert(step, at: index + 1)
        updateScript(script)
        selectedStepID = step.id
    }

    func moveStep(_ id: UUID, by offset: Int) {
        guard var script = selectedScript, let index = script.steps.firstIndex(where: { $0.id == id }), script.steps.indices.contains(index + offset) else { return }
        script.steps.swapAt(index, index + offset)
        updateScript(script)
    }

    func importScript() {
        guard canEdit else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "选择鼠标精灵导出的 JSON 脚本"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard workspace.scripts.count < 500 else { throw ValidationError.invalid("脚本库最多保存 500 个脚本。") }
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= WorkspaceRepository.maximumScriptBytes else { throw ValidationError.invalid("导入文件不能超过 5 MB。") }
            let script = try WorkspaceRepository.importScript(from: Data(contentsOf: url))
            workspace.scripts.insert(script, at: 0)
            selectedScriptID = script.id
            section = .recording
            log("已导入「\(script.name)」")
            save()
        } catch { report("导入失败：\(error.localizedDescription)") }
    }

    func exportScript() {
        guard let script = selectedScript else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = script.name.replacingOccurrences(of: "/", with: "-") + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try WorkspaceRepository.exportScript(script).write(to: url, options: .atomic); log("已导出「\(script.name)」") }
        catch { report("导出失败：\(error.localizedDescription)") }
    }

    func hotkeyLabel(_ action: HotkeyAction) -> String { workspace.preferences.hotkeys[action]?.label ?? "未设置" }

    func runOrPause() {
        if engine.isActive { engine.pauseResume() }
        else if runTarget == .clicking { startClicking() }
        else { togglePlayback() }
    }

    func applyHotkeys() {
        guard systemIntegration else { return }
        hotkeyErrors = hotkeys.register(workspace.preferences.hotkeys) { [weak self] action in
            guard let self else { return }
            switch action {
            case .stop: self.stopAll()
            case .record: self.toggleRecording()
            case .pick: self.pickPosition()
            case .runPause: self.runOrPause()
            }
        }
        if !hotkeyErrors.isEmpty { log("部分全局快捷键注册失败，请在设置中检查冲突。") }
    }

    func restoreHotkeys() {
        workspace.preferences.hotkeys = AppPreferences().hotkeys
        applyHotkeys()
    }

    func clearLogs() { logs = [] }

    func save() {
        persist(showErrors: true)
    }

    private func persist(showErrors: Bool) {
        saveTask?.cancel(); saveTask = nil
        guard !storageBlocked else {
            if showErrors { errorMessage = "工作区原文件无法读取，已暂停自动保存以保护它。请先在设置中打开数据目录，备份或修复 workspace.json 后重启应用。当前脚本仍可单独导出。" }
            return
        }
        do { try repository.save(workspace); pendingChanges = false; lastSaveError = nil }
        catch {
            pendingChanges = true
            lastSaveError = error.localizedDescription
            // A text field may be temporarily empty while editing. Do not interrupt
            // typing with a modal; explicit save and execution still validate.
            if showErrors { errorMessage = "保存失败：\(error.localizedDescription)" }
        }
    }

    @discardableResult func shutdown() -> Bool {
        stopAll(); save(); hotkeys.unregisterAll()
        guard !pendingChanges else {
            if systemIntegration { applyHotkeys() }
            return false
        }
        refreshTimer?.invalidate(); refreshTimer = nil
        return true
    }

    func openDataDirectory() {
        do {
            try FileManager.default.createDirectory(at: repository.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            NSWorkspace.shared.open(repository.url.deletingLastPathComponent())
        } catch { report(error.localizedDescription) }
    }

    private func scheduleSave() {
        pendingChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.persist(showErrors: false)
        }
    }

    private func report(_ message: String) { errorMessage = message; log(message) }
    private func log(_ message: String) {
        logs.insert(ActivityEntry(message: message), at: 0)
        if logs.count > 200 { logs.removeLast(logs.count - 200) }
    }
}
