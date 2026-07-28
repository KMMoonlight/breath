import AppKit
import BreathCore
import SwiftUI

struct AgentBrandIcon: View {
    private static let iconCount: CGFloat = 9
    private static let sprite = BreathResources.bundle
        .url(forResource: "AgentBrandIcons", withExtension: "svg")
        .flatMap(NSImage.init(contentsOf:))

    let agent: AgentKind
    let color: Color
    let glyphSize: CGFloat
    let frameSize: CGFloat

    init(
        agent: AgentKind,
        color: Color = .secondary,
        glyphSize: CGFloat = 14,
        frameSize: CGFloat = 16
    ) {
        self.agent = agent
        self.color = color
        self.glyphSize = glyphSize
        self.frameSize = frameSize
    }

    var body: some View {
        Group {
            if let sprite = Self.sprite {
                GeometryReader { _ in
                    Image(nsImage: sprite)
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .frame(
                            width: glyphSize * Self.iconCount,
                            height: glyphSize
                        )
                        .offset(
                            x: -CGFloat(agent.brandIconIndex) * glyphSize
                        )
                }
                .frame(width: glyphSize, height: glyphSize)
                .clipped()
            } else {
                Image(systemName: "terminal")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: glyphSize - 1, weight: .medium))
            }
        }
        .foregroundStyle(color)
        .frame(width: frameSize, height: frameSize)
    }
}

extension AgentKind {
    var brandIconIndex: Int {
        switch self {
        case .codex: 0
        case .claudeCode: 1
        case .geminiCLI: 2
        case .githubCopilotCLI: 3
        case .qwenCode: 4
        case .cursorAgent: 5
        case .factoryDroid: 6
        case .openCode: 7
        case .pi: 8
        }
    }
}
