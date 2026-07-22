import BreathCore
import Foundation
import Testing
@testable import BreathApp

@Suite("Work Session Tab presentation")
struct WorkSessionTabPresentationTests {
    @Test("placeholder title omits its creation time")
    func placeholderTitleOmitsTime() {
        let presentation = WorkSessionTabPresentation(
            session: placeholderSession,
            index: 0,
            placeholderTitle: "新会话"
        )

        #expect(presentation.title == "新会话")
    }

    @Test("the first nine tabs always expose their command number")
    func firstNineTabsShowCommandNumber() {
        let first = WorkSessionTabPresentation(
            session: placeholderSession,
            index: 0,
            placeholderTitle: "新会话"
        )
        let ninth = WorkSessionTabPresentation(
            session: placeholderSession,
            index: 8,
            placeholderTitle: "新会话"
        )
        let tenth = WorkSessionTabPresentation(
            session: placeholderSession,
            index: 9,
            placeholderTitle: "新会话"
        )

        #expect(first.shortcutLabel == "⌘1")
        #expect(ninth.shortcutLabel == "⌘9")
        #expect(tenth.shortcutLabel == nil)
    }

    @Test("an Agent native title remains visible")
    func agentNativeTitleRemainsVisible() {
        var session = placeholderSession
        session.title = "修复登录流程"
        session.titleSource = .agentNative

        let presentation = WorkSessionTabPresentation(
            session: session,
            index: 0,
            placeholderTitle: "新会话"
        )

        #expect(presentation.title == "修复登录流程")
    }

    private var placeholderSession: WorkSession {
        WorkSession(
            id: WorkSessionID(rawValue: UUID()),
            workspaceID: WorkspaceID(rawValue: UUID()),
            title: "新会话 · 13:39",
            pane: TerminalPane(id: TerminalPaneID(rawValue: UUID()))
        )
    }
}
