import AppKit
import SwiftUI

@MainActor
protocol MainWindowPresenting: AnyObject {
    var isVisible: Bool { get }
    var isMiniaturized: Bool { get }
    func deminiaturize(_ sender: Any?)
    func makeKeyAndOrderFront(_ sender: Any?)
}

extension NSWindow: MainWindowPresenting {}

/// The SwiftUI scene owns its window. Closing it may destroy the NSWindow, so
/// retain the scene-opening action, not the window or its content view.
@MainActor
final class MainWindowController {
    private weak var window: (any MainWindowPresenting)?
    var openNewWindow: (@MainActor () -> Void)?
    private let activate: @MainActor () -> Void

    init(activate: @escaping @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }) {
        self.activate = activate
    }

    func register(_ window: any MainWindowPresenting) { self.window = window }

    @discardableResult
    func show() -> Bool {
        if let window, window.isVisible || window.isMiniaturized {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            guard let openNewWindow else { return false }
            openNewWindow()
        }
        activate()
        return true
    }
}

struct MainWindowRegistration: NSViewRepresentable {
    let controller: MainWindowController

    func makeNSView(context: Context) -> WindowRegistrationView {
        let view = WindowRegistrationView()
        view.controller = controller
        return view
    }

    func updateNSView(_ view: WindowRegistrationView, context: Context) {
        view.controller = controller
        if let window = view.window { controller.register(window) }
    }
}

final class WindowRegistrationView: NSView {
    weak var controller: MainWindowController?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // An old view detaching must not clear a newer window's registration.
        if let window { controller?.register(window) }
    }
}
