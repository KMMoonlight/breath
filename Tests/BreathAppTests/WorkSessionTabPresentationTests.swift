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
            isSelected: true,
            placeholderTitle: "新会话"
        )

        #expect(presentation.title == "新会话")
    }

    @Test("only the selected first nine tabs expose their command number")
    func selectedTabShowsCommandNumber() {
        let selected = WorkSessionTabPresentation(
            session: placeholderSession,
            index: 2,
            isSelected: true,
            placeholderTitle: "新会话"
        )
        let unselected = WorkSessionTabPresentation(
            session: placeholderSession,
            index: 2,
            isSelected: false,
            placeholderTitle: "新会话"
        )
        let tenth = WorkSessionTabPresentation(
            session: placeholderSession,
            index: 9,
            isSelected: true,
            placeholderTitle: "新会话"
        )

        #expect(selected.shortcutLabel == "⌘3")
        #expect(unselected.shortcutLabel == nil)
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
            isSelected: true,
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
