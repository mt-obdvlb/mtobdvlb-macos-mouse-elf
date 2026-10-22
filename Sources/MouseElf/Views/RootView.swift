import SwiftUI
import MouseElfCore

struct RootView: View {
    @Bindable var store: AppStore
    private let sections: [WorkspaceSection] = [.tasks, .recording, .library, .settings]

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 22, weight: .semibold)).foregroundStyle(.teal)
                        .frame(width: 40, height: 40).background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("鼠标精灵").font(.headline)
                        Text("MAC AUTOMATION").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 24)
                List(selection: Binding<WorkspaceSection?>(get: { store.section }, set: { if let value = $0 { store.section = value } })) {
                    Section("工作台") {
                        ForEach(sections, id: \.self) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section).padding(.vertical, 5)
                                .accessibilityIdentifier("nav_\(String(describing: section))")
                        }
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        StatusDot(active: store.engine.isActive || store.recorder.isRecording)
                        Text(store.recorder.isRecording ? "正在录制" : store.engine.isActive ? "任务进行中" : "准备就绪").font(.caption)
                    }
                    HStack {
                        Text("随时停止").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        ShortcutBadge(text: store.hotkeyLabel(.stop))
                    }
                }.padding(16)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if let notice = store.notice {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
                        Text(notice).font(.callout)
                        Spacer()
                        Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭提示")
                    }.padding(.horizontal, 24).padding(.vertical, 10).background(.teal.opacity(0.08))
                }
                switch store.section {
                case .tasks: TasksView(store: store)
                case .recording: RecordingView(store: store)
                case .library: LibraryView(store: store)
                case .settings: SettingsView(store: store)
                }
            }
        }
        .navigationTitle(store.section.title)
        .tint(.teal)
        .frame(minWidth: 1000, minHeight: 700)
        .preferredColorScheme(colorScheme)
        .alert("操作未完成", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var colorScheme: ColorScheme? {
        switch store.workspace.preferences.theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
