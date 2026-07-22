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
            placeholderTitle: "新会话"
        )

        #expect(presentation.title == "新会话")
    }

    @Test("only the selected first nine tabs expose their command number")
    func selectedTabShowsCommandNumber() {
        let presentation = WorkSessionTabPresentation(
            session: placeholderSession,
            placeholderTitle: "新会话"
        )

        #expect(presentation.shortcutLabel(at: 2, isSelected: true) == "⌘3")
        #expect(presentation.shortcutLabel(at: 2, isSelected: false) == nil)
        #expect(presentation.shortcutLabel(at: 9, isSelected: true) == nil)
    }

    @Test("an existing non-placeholder title remains visible")
    func existingTitleRemainsVisible() {
        var session = placeholderSession
        session.title = "修复登录流程"

        let presentation = WorkSessionTabPresentation(
            session: session,
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
