import SwiftUI

private struct HoverTooltipModifier: ViewModifier {
    let text: String

    @State private var isHovered = false
    @State private var isPresented = false
    @State private var presentationTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovered = hovering
                presentationTask?.cancel()
                presentationTask = nil

                if hovering {
                    presentationTask = Task { @MainActor in
                        do {
                            try await Task.sleep(for: .milliseconds(300))
                        } catch {
                            return
                        }
                        guard !Task.isCancelled, isHovered else { return }
                        isPresented = true
                    }
                } else {
                    isPresented = false
                }
            }
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(
                        minWidth: 160,
                        idealWidth: 280,
                        maxWidth: 360,
                        alignment: .leading
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .onDisappear {
                presentationTask?.cancel()
                presentationTask = nil
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
