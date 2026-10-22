import SwiftUI
import MouseElfCore

struct LibraryView: View {
    @Bindable var store: AppStore
    @State private var search = ""
    @State private var pendingDeletion: MouseScript?
    private var scripts: [MouseScript] {
        store.workspace.scripts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    PageHeading(title: "你的自动化工具箱。", subtitle: "每个保存的流程，都是下一次少做的重复工作。")
                    Spacer()
                    Button { store.newScript() } label: { Label("新建脚本", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).disabled(!store.canEdit).accessibilityIdentifier("newLibraryScript")
                }
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索脚本", text: $search).textFieldStyle(.plain).accessibilityIdentifier("searchScripts")
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("清除搜索") }
                    }.padding(8).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 7)).frame(maxWidth: 300)
                    Spacer()
                    Text("\(store.workspace.scripts.count) 个脚本").font(.callout).foregroundStyle(.secondary)
                    Button { store.importScript() } label: { Label("导入 JSON", systemImage: "square.and.arrow.down") }
                        .disabled(!store.canEdit).accessibilityIdentifier("importScript")
                }
            }.padding(28)
            Divider()
            if store.workspace.scripts.isEmpty {
                VStack(spacing: 0) {
                    EmptyWorkspace(title: "还没有保存的脚本", description: "在录制页捕捉一段操作，或者导入已有的 JSON 脚本。所有脚本都保存在本机。", image: "square.stack.3d.up")
                    Button { store.section = .recording } label: { Label("开始一次录制", systemImage: "record.circle") }.controlSize(.large).padding(.bottom, 50)
                }
            } else if scripts.isEmpty {
                EmptyWorkspace(title: "没有匹配的脚本", description: "试试其他名称，或清空搜索查看全部脚本。", image: "magnifyingglass")
            } else {
                List {
                    ForEach(scripts) { script in
                        libraryRow(script)
                    }
                }.listStyle(.inset).accessibilityIdentifier("scriptLibrary")
            }
        }
        .alert("删除脚本？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button("取消", role: .cancel) { pendingDeletion = nil }
            Button("删除", role: .destructive) {
                if let script = pendingDeletion { store.deleteScript(script.id) }
                pendingDeletion = nil
            }
        } message: { Text("「\(pendingDeletion?.name ?? "")」及其步骤将从本机脚本库删除。") }
    }

    private func libraryRow(_ script: MouseScript) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.text").font(.system(size: 24, weight: .light)).foregroundStyle(.teal)
                .frame(width: 48, height: 52).background(.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 7) {
                Text(script.name).font(.headline).lineLimit(1)
                HStack(spacing: 14) {
                    Label("\(script.steps.count) 个步骤", systemImage: "list.bullet")
                    Text(script.loopCount == 0 ? "持续循环" : "循环 \(script.loopCount) 次")
                    Text("\(script.speed.formatted())×")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(script.updatedAt, format: .dateTime.month(.twoDigits).day(.twoDigits)).font(.callout).foregroundStyle(.secondary)
                Text("最近修改").font(.caption2).foregroundStyle(.tertiary)
            }
            Button("打开编辑") { store.selectScript(script.id) }.disabled(!store.canEdit).accessibilityLabel("编辑脚本 \(script.name)")
            Menu {
                Button("复制脚本") { store.duplicateScript(script.id) }
                Button("导出 JSON") { store.selectedScriptID = script.id; store.exportScript() }
                Divider()
                Button("删除脚本", role: .destructive) { pendingDeletion = script }
            } label: { Image(systemName: "ellipsis").frame(width: 20) }
                .menuStyle(.borderlessButton).frame(width: 25).disabled(!store.canEdit)
                .accessibilityLabel("脚本 \(script.name) 的更多操作")
        }.padding(.vertical, 14)
            .contextMenu {
                Group {
                    Button("打开编辑") { store.selectScript(script.id) }
                    Button("复制脚本") { store.duplicateScript(script.id) }
                    Button("导出 JSON") { store.selectedScriptID = script.id; store.exportScript() }
                    Divider()
                    Button("删除脚本", role: .destructive) { pendingDeletion = script }
                }.disabled(!store.canEdit)
            }
    }
}
