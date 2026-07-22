import Foundation
import Testing
@testable import BreathCore

@Suite("Workbench navigation")
struct WorkbenchNavigationTests {
    @Test("next tab cycles through active sessions in the selected workspace")
    func nextTabCyclesWithinWorkspace() {
        let firstWorkspaceID = WorkspaceID(rawValue: UUID())
        let secondWorkspaceID = WorkspaceID(rawValue: UUID())
        let firstSessionID = WorkSessionID(rawValue: UUID())
        let secondSessionID = WorkSessionID(rawValue: UUID())
        let archivedSessionID = WorkSessionID(rawValue: UUID())
        let otherWorkspaceSessionID = WorkSessionID(rawValue: UUID())
        let snapshot = WorkbenchSnapshot(
            workspaces: [
                Workspace(id: firstWorkspaceID, path: "/tmp/first", displayName: "First"),
                Workspace(id: secondWorkspaceID, path: "/tmp/second", displayName: "Second"),
            ],
            workSessions: [
                session(id: firstSessionID, workspaceID: firstWorkspaceID),
                session(id: secondSessionID, workspaceID: firstWorkspaceID),
                session(
                    id: archivedSessionID,
                    workspaceID: firstWorkspaceID,
                    archivedAt: Date(timeIntervalSince1970: 1)
                ),
                session(id: otherWorkspaceSessionID, workspaceID: secondWorkspaceID),
            ],
            selectedWorkSessionID: firstSessionID
        )

        #expect(snapshot.nextActiveWorkSessionID(in: firstWorkspaceID) == secondSessionID)

        var wrappedSnapshot = snapshot
        wrappedSnapshot.selectedWorkSessionID = secondSessionID
        #expect(wrappedSnapshot.nextActiveWorkSessionID(in: firstWorkspaceID) == firstSessionID)
    }

    @Test("a workspace with fewer than two active sessions has no next tab")
    func nextTabRequiresAnotherActiveSession() {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        let snapshot = WorkbenchSnapshot(
            workspaces: [
                Workspace(id: workspaceID, path: "/tmp/only", displayName: "Only"),
            ],
            workSessions: [session(id: sessionID, workspaceID: workspaceID)],
            selectedWorkSessionID: sessionID
        )

        #expect(snapshot.nextActiveWorkSessionID(in: workspaceID) == nil)
    }

    @Test("pane navigation follows layout order and wraps at both ends")
    func paneNavigationCyclesInLayoutOrder() {
        let firstPaneID = TerminalPaneID(rawValue: UUID())
        let secondPaneID = TerminalPaneID(rawValue: UUID())
        let thirdPaneID = TerminalPaneID(rawValue: UUID())
        let layout = PaneLayout.split(
            orientation: .horizontal,
            fraction: 0.4,
            first: .pane(TerminalPane(id: firstPaneID)),
            second: .split(
                orientation: .vertical,
                fraction: 0.5,
                first: .pane(TerminalPane(id: secondPaneID)),
                second: .pane(TerminalPane(id: thirdPaneID))
            )
        )

        #expect(layout.previousPaneID(from: firstPaneID) == thirdPaneID)
        #expect(layout.nextPaneID(from: firstPaneID) == secondPaneID)
        #expect(layout.previousPaneID(from: secondPaneID) == firstPaneID)
        #expect(layout.nextPaneID(from: thirdPaneID) == firstPaneID)
    }

    @Test("a single-pane layout has no adjacent pane")
    func paneNavigationRequiresAnotherPane() {
        let paneID = TerminalPaneID(rawValue: UUID())
        let layout = PaneLayout.pane(TerminalPane(id: paneID))

        #expect(layout.previousPaneID(from: paneID) == nil)
        #expect(layout.nextPaneID(from: paneID) == nil)
    }

    private func session(
        id: WorkSessionID,
        workspaceID: WorkspaceID,
        archivedAt: Date? = nil
    ) -> WorkSession {
        WorkSession(
            id: id,
            workspaceID: workspaceID,
            title: "Session",
            pane: TerminalPane(id: TerminalPaneID(rawValue: UUID())),
            archivedAt: archivedAt
        )
    }
}
