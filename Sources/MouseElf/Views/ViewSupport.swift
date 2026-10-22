import SwiftUI
import MouseElfCore

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct Panel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: systemImage).font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
    }
}

struct FieldCaption: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ShortcutBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct StatusDot: View {
    var active: Bool
    var body: some View { Circle().fill(active ? Color.teal : Color.secondary.opacity(0.45)).frame(width: 7, height: 7) }
}

struct EmptyWorkspace: View {
    let title: String
    let description: String
    let image: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: image).font(.system(size: 36, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(description).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }
}

struct RunControls: View {
    @Bindable var store: AppStore
    var body: some View {
        HStack(spacing: 10) {
            if store.engine.isActive {
                Button { store.engine.pauseResume() } label: {
                    Label(store.engine.phase == .paused ? "继续" : "暂停", systemImage: store.engine.phase == .paused ? "play.fill" : "pause.fill")
                }.disabled(store.engine.phase == .countdown)
                    .accessibilityIdentifier("pauseRun")
                Button(role: .destructive) { store.stopAll() } label: { Label("停止", systemImage: "stop.fill") }
                    .accessibilityIdentifier("stopRun")
            }
        }.controlSize(.large)
    }
}

func durationLabel(_ milliseconds: Double) -> String {
    guard milliseconds.isFinite, milliseconds >= 0 else { return "—" }
    if milliseconds < 1000 { return "\(Int(milliseconds)) ms" }
    return String(format: "%.1f 秒", milliseconds / 1000)
}
