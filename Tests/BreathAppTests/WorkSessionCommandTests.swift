import BreathCore
import Foundation
import Testing
@testable import BreathApp

@Suite("Work session commands")
struct WorkSessionCommandTests {
    @Test("tab and pane navigation appear in the shortcuts reference")
    func navigationAppearsInShortcutsReference() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/BreathSettingsView.swift"),
            encoding: .utf8
        )

        #expect(
            source.contains(
                "ShortcutReference(action: \"新建工作会话\", keys: \"⌘T\")"
            )
        )
        #expect(
            source.contains(
                "ShortcutReference(action: \"下一个会话 Tab\", keys: \"⌘N\")"
            )
        )
        #expect(
            source.contains(
                "ShortcutReference(action: \"上一个分屏\", keys: \"⌘[\")"
            )
        )
        #expect(
            source.contains(
                "ShortcutReference(action: \"下一个分屏\", keys: \"⌘]\")"
            )
        )
        #expect(!source.contains("切换到第 1–9 个终端"))
    }

    @Test("current workspace follows the selected work session")
    @MainActor
    func currentWorkspaceFollowsSelection() throws {
        let firstWorkspaceID = WorkspaceID(rawValue: UUID())
        let secondWorkspaceID = WorkspaceID(rawValue: UUID())
        let selectedSessionID = WorkSessionID(rawValue: UUID())
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-command-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }

        let harness = try AppShellTestingHarness(
            snapshot: WorkbenchSnapshot(
                workspaces: [
                    Workspace(id: firstWorkspaceID, path: "/tmp/first", displayName: "First"),
                    Workspace(id: secondWorkspaceID, path: "/tmp/second", displayName: "Second"),
                ],
                workSessions: [
                    WorkSession(
                        id: WorkSessionID(rawValue: UUID()),
                        workspaceID: firstWorkspaceID,
                        title: "First session",
                        pane: TerminalPane(id: TerminalPaneID(rawValue: UUID()))
                    ),
                    WorkSession(
                        id: selectedSessionID,
                        workspaceID: secondWorkspaceID,
                        title: "Selected session",
                        pane: TerminalPane(id: TerminalPaneID(rawValue: UUID()))
                    ),
                ],
                selectedWorkSessionID: selectedSessionID
            ),
            supportDirectory: supportDirectory
        )

        #expect(harness.model.currentWorkspaceID == secondWorkspaceID)
    }
}
