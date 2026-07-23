import AppKit
import SwiftUI

private struct BreathWindowFullScreenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var breathWindowIsFullScreen: Bool {
        get { self[BreathWindowFullScreenKey.self] }
        set { self[BreathWindowFullScreenKey.self] = newValue }
    }
}

private struct PageToolbarLeadingPadding: ViewModifier {
    @Environment(\.breathWindowIsFullScreen) private var isFullScreen

    func body(content: Content) -> some View {
        content.padding(
            .leading,
            WorkbenchLayout.pageToolbarLeadingInset(
                isFullScreen: isFullScreen
            )
        )
    }
}

extension View {
    func pageToolbarLeadingPadding() -> some View {
        modifier(PageToolbarLeadingPadding())
    }
}

struct WindowFullScreenObserver: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> WindowFullScreenObservationView {
        let view = WindowFullScreenObservationView()
        configure(view)
        return view
    }

    func updateNSView(
        _ nsView: WindowFullScreenObservationView,
        context: Context
    ) {
        configure(nsView)
    }

    private func configure(_ view: WindowFullScreenObservationView) {
        view.onChange = { fullScreen in
            guard isFullScreen != fullScreen else { return }
            isFullScreen = fullScreen
        }
        view.synchronizeFullScreenState()
    }
}

@MainActor
final class WindowFullScreenObservationView: NSView {
    var onChange: ((Bool) -> Void)?

    private weak var monitoredWindow: NSWindow?
    private var lastReportedState: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowObservation()
    }

    func synchronizeFullScreenState() {
        let fullScreen = window?.styleMask.contains(.fullScreen) == true
        guard lastReportedState != fullScreen else { return }
        lastReportedState = fullScreen
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(fullScreen)
        }
    }

    private func updateWindowObservation() {
        if let monitoredWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didEnterFullScreenNotification,
                object: monitoredWindow
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didExitFullScreenNotification,
                object: monitoredWindow
            )
        }

        monitoredWindow = window
        guard let window else {
            synchronizeFullScreenState()
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowFullScreenStateDidChange),
            name: NSWindow.didEnterFullScreenNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowFullScreenStateDidChange),
            name: NSWindow.didExitFullScreenNotification,
            object: window
        )
        synchronizeFullScreenState()
    }

    @objc
    private func windowFullScreenStateDidChange() {
        synchronizeFullScreenState()
    }
}
