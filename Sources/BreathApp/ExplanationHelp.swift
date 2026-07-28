import AppKit
import SwiftUI

private struct TooltipBubble: View {
    let text: String
    let width: CGFloat

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Color(nsColor: .labelColor))
            .multilineTextAlignment(.leading)
            .frame(width: width - 20, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

private final class TooltipAnchor {
    weak var view: NSView?

    @MainActor
    func screenRect() -> NSRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

private struct TooltipAnchorReader: NSViewRepresentable {
    let anchor: TooltipAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }

    static func dismantleNSView(_ view: NSView, coordinator: Void) {
        TooltipController.shared.dismiss()
    }
}

/// Presents explanation tooltips in a plain, opaque panel instead of a system
/// popover, so long text wraps fully and the chrome never uses the system's
/// translucent "liquid glass" styling.
///
/// SwiftUI's `onHover` exit callback is unreliable for the tiny info icon, so
/// the controller tracks the pointer itself: it shows the tooltip once the
/// pointer has rested for 300ms and dismisses it as soon as the pointer moves
/// away, clicks, or scrolls.
@MainActor
private final class TooltipController {
    static let shared = TooltipController()

    private static let maximumWidth: CGFloat = 340
    private static let horizontalPadding: CGFloat = 20
    private static let anchorGap: CGFloat = 6
    private static let anchorLeadingInset: CGFloat = 8
    private static let screenInset: CGFloat = 4

    private var panel: NSPanel?
    private var pendingTask: Task<Void, Never>?
    private var eventMonitor: Any?
    private var restPoint = NSPoint.zero

    func pointerDidRest(
        onIcon text: String,
        anchorRect: NSRect,
        darkAppearance: Bool
    ) {
        dismiss()
        restPoint = NSEvent.mouseLocation
        startMonitoring()
        pendingTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            show(
                text: text,
                below: anchorRect,
                darkAppearance: darkAppearance
            )
        }
    }

    func dismiss() {
        pendingTask?.cancel()
        pendingTask = nil
        panel?.orderOut(nil)
        panel = nil
        stopMonitoring()
    }

    private func startMonitoring() {
        stopMonitoring()
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .mouseMoved, .scrollWheel,
                .leftMouseDown, .rightMouseDown, .otherMouseDown,
            ]
        ) { [weak self] event in
            guard let self else { return event }
            let point = NSEvent.mouseLocation
            let movedAway =
                abs(point.x - restPoint.x) > 16
                || abs(point.y - restPoint.y) > 16
            if event.type != .mouseMoved || movedAway {
                dismiss()
            }
            return event
        }
    }

    private func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    /// Places the tooltip directly below the info icon that owns it.
    /// The appearance is passed in from the SwiftUI color scheme because the
    /// app applies appearance per window, so `NSApp.effectiveAppearance`
    /// would fall back to light.
    private func show(
        text: String,
        below anchorRect: NSRect,
        darkAppearance: Bool
    ) {
        panel?.orderOut(nil)

        let width = tooltipWidth(for: text)
        let hostingView = NSHostingView(
            rootView: TooltipBubble(text: text, width: width)
        )
        let size = hostingView.fittingSize

        var origin = NSPoint(
            x: anchorRect.midX - Self.anchorLeadingInset,
            y: anchorRect.minY - size.height - Self.anchorGap
        )
        let anchorPoint = NSPoint(x: anchorRect.midX, y: anchorRect.midY)
        let screen = NSScreen.screens.first {
            NSMouseInRect(anchorPoint, $0.frame, false)
        } ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            origin.x = min(
                max(origin.x, visibleFrame.minX + Self.screenInset),
                visibleFrame.maxX - size.width - Self.screenInset
            )
            if origin.y < visibleFrame.minY {
                origin.y = anchorRect.maxY + Self.anchorGap
            }
            origin.y = min(
                origin.y,
                visibleFrame.maxY - size.height - Self.screenInset
            )
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(
            named: darkAppearance ? .darkAqua : .aqua
        )
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func tooltipWidth(for text: String) -> CGFloat {
        let textView = NSHostingView(
            rootView: Text(text)
                .font(.callout)
                .fixedSize()
        )
        return min(
            ceil(textView.fittingSize.width) + Self.horizontalPadding,
            Self.maximumWidth
        )
    }
}

private struct HoverTooltipModifier: ViewModifier {
    let text: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var anchor = TooltipAnchor()

    func body(content: Content) -> some View {
        content
            .background {
                TooltipAnchorReader(anchor: anchor)
                    .allowsHitTesting(false)
            }
            .onHover { hovering in
                if hovering, let anchorRect = anchor.screenRect() {
                    TooltipController.shared.pointerDidRest(
                        onIcon: text,
                        anchorRect: anchorRect,
                        darkAppearance: colorScheme == .dark
                    )
                } else {
                    TooltipController.shared.dismiss()
                }
            }
            .onDisappear {
                TooltipController.shared.dismiss()
            }
    }
}

extension View {
    func hoverTooltip(_ text: String) -> some View {
        modifier(HoverTooltipModifier(text: text))
    }
}

struct ExplanationLabel<Content: View>: View {
    let explanation: String
    let content: Content

    init(
        _ explanation: String,
        @ViewBuilder content: () -> Content
    ) {
        self.explanation = explanation
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 4) {
            content
                .accessibilityHint(explanation)
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
                .hoverTooltip(explanation)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
