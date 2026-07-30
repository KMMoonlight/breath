import SwiftUI

enum BreathEmptyStateStyle: Equatable {
    case standard
    case passive
}

enum BreathEmptyStatePlacement {
    case canvas
    case inline
}

enum BreathEmptyStateMetrics {
    static let iconSize: CGFloat = 20
    static let inlineIconSize: CGFloat = 14
    static let contentSpacing: CGFloat = 7
    static let textSpacing: CGFloat = 3
    static let actionTopPadding: CGFloat = 2
    static let canvasPadding: CGFloat = 20
    static let inlineVerticalPadding: CGFloat = 4
    static let maxTextWidth: CGFloat = 340
}

struct BreathEmptyState<Actions: View>: View {
    let title: String
    let systemImage: String?
    let message: String?
    let style: BreathEmptyStateStyle
    let placement: BreathEmptyStatePlacement
    private let actions: Actions

    init(
        title: String,
        systemImage: String? = nil,
        message: String? = nil,
        style: BreathEmptyStateStyle = .standard,
        placement: BreathEmptyStatePlacement = .canvas,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.style = style
        self.placement = placement
        self.actions = actions()
    }

    @ViewBuilder
    var body: some View {
        switch placement {
        case .canvas:
            canvasContent
                .padding(BreathEmptyStateMetrics.canvasPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .inline:
            inlineContent
                .padding(.vertical, BreathEmptyStateMetrics.inlineVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var canvasContent: some View {
        VStack(spacing: BreathEmptyStateMetrics.contentSpacing) {
            if style == .standard, let systemImage {
                Image(systemName: systemImage)
                    .font(
                        .system(
                            size: BreathEmptyStateMetrics.iconSize,
                            weight: .regular
                        )
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            textBlock(alignment: .center)

            actions
                .controlSize(.small)
                .padding(.top, BreathEmptyStateMetrics.actionTopPadding)
        }
        .frame(maxWidth: BreathEmptyStateMetrics.maxTextWidth)
    }

    private var inlineContent: some View {
        HStack(spacing: BreathEmptyStateMetrics.contentSpacing) {
            if style == .standard, let systemImage {
                Image(systemName: systemImage)
                    .font(
                        .system(
                            size: BreathEmptyStateMetrics.inlineIconSize,
                            weight: .regular
                        )
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            textBlock(alignment: .leading)
            Spacer(minLength: BreathEmptyStateMetrics.contentSpacing)
            actions.controlSize(.small)
        }
    }

    private func textBlock(alignment: TextAlignment) -> some View {
        VStack(
            alignment: horizontalAlignment(for: alignment),
            spacing: BreathEmptyStateMetrics.textSpacing
        ) {
            titleText

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(alignment)
        .accessibilityElement(children: .combine)
    }

    private func horizontalAlignment(
        for textAlignment: TextAlignment
    ) -> HorizontalAlignment {
        switch textAlignment {
        case .leading:
            .leading
        case .center:
            .center
        case .trailing:
            .trailing
        }
    }

    @ViewBuilder
    private var titleText: some View {
        switch style {
        case .standard:
            Text(title)
                .font(.callout.weight(.medium))
        case .passive:
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension BreathEmptyState where Actions == EmptyView {
    init(
        title: String,
        systemImage: String? = nil,
        message: String? = nil,
        style: BreathEmptyStateStyle = .standard,
        placement: BreathEmptyStatePlacement = .canvas
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            message: message,
            style: style,
            placement: placement
        ) {
            EmptyView()
        }
    }
}
