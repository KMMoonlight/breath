#if DEBUG
import AppKit
import BreathCore
import SwiftUI
import Vision

@MainActor
enum AppShellEmptyStateVerifier {
    static func run(resultURL: URL?) -> Int32 {
        do {
            try verify()
            writeResult("ok", to: resultURL)
            return 0
        } catch {
            let message = "App Shell empty-state verification failed: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            writeResult(message, to: resultURL)
            return 1
        }
    }

    private static func writeResult(_ result: String, to url: URL?) {
        guard let url else { return }
        try? Data(result.utf8).write(to: url, options: .atomic)
    }

    private static func verify() throws {
        let fixture = try AppShellFixture(snapshot: .empty)
        defer { fixture.close() }
        var failures: [String] = []

        var visibleText = try fixture.renderedText(WorkbenchView(model: fixture.model))
        require(visibleText.contains("工作区"), "empty workbench did not render its sidebar", into: &failures)
        require(!visibleText.contains("还没有工作区"), "empty workspace title is still visible", into: &failures)
        require(
            !visibleText.contains("添加一个项目目录以打开第一个空终端"),
            "empty workspace description is still visible",
            into: &failures
        )
        require(!visibleText.contains("选择一个工作会话"), "selection title is still visible", into: &failures)
        require(
            !visibleText.contains("只会在选中时恢复对应布局"),
            "selection description is still visible",
            into: &failures
        )
        require(
            WorkbenchAccessibility.addWorkspace == "添加工作区",
            "add workspace action lost its accessibility label",
            into: &failures
        )
        require(
            WorkbenchAccessibility.noSelectedWorkSession == "没有选中的工作会话",
            "blank terminal canvas lost its accessibility status",
            into: &failures
        )

        let activeSessionSnapshot = makeSnapshotWithActiveSession()
        fixture.use(activeSessionSnapshot)
        visibleText = try fixture.renderedText(WorkbenchView(model: fixture.model))
        require(visibleText.contains("示例项目"), "workspace tree did not render", into: &failures)
        require(!visibleText.contains("选择一个工作会话"), "selection title is visible with a workspace", into: &failures)
        require(fixture.model.snapshot == activeSessionSnapshot, "rendering changed the active-session snapshot", into: &failures)

        let workspaceID = WorkspaceID(rawValue: UUID())
        let noSessionsSnapshot = WorkbenchSnapshot(
            workspaces: [Workspace(id: workspaceID, path: "/tmp", displayName: "空项目")],
            workSessions: [],
            selectedWorkSessionID: nil
        )
        fixture.use(noSessionsSnapshot)
        visibleText = try fixture.renderedText(WorkbenchView(model: fixture.model))
        require(visibleText.contains("空项目"), "workspace without sessions did not render", into: &failures)
        require(!visibleText.contains("选择一个工作会话"), "selection title is visible without sessions", into: &failures)
        require(fixture.model.snapshot == noSessionsSnapshot, "rendering created or selected a session", into: &failures)

        let settingsText = try fixture.renderedText(
            BreathSettingsView(model: fixture.model, selectedTab: .archives)
        )
        require(settingsText.contains("已归档"), "archived settings tab did not render", into: &failures)
        require(!settingsText.contains("没有已归档会话"), "archived settings still use the large empty title", into: &failures)

        guard failures.isEmpty else {
            throw AppShellVerificationError.failed(failures)
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        into failures: inout [String]
    ) {
        if !condition() {
            failures.append(message)
        }
    }

    private static func makeSnapshotWithActiveSession() -> WorkbenchSnapshot {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let sessionID = WorkSessionID(rawValue: UUID())
        return WorkbenchSnapshot(
            workspaces: [Workspace(id: workspaceID, path: "/tmp", displayName: "示例项目")],
            workSessions: [
                WorkSession(
                    id: sessionID,
                    workspaceID: workspaceID,
                    title: "Agent 对话摘要",
                    pane: TerminalPane(id: TerminalPaneID(rawValue: UUID()))
                ),
            ],
            selectedWorkSessionID: nil
        )
    }
}

@MainActor
private final class AppShellFixture {
    let model: BreathApplicationModel
    private let supportDirectory: URL
    private var window: NSWindow?

    init(snapshot: WorkbenchSnapshot) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-app-shell-\(UUID().uuidString)", isDirectory: true)
        model = try BreathApplicationModel.makeTesting(
            snapshot: snapshot,
            supportDirectory: supportDirectory
        )
    }

    func renderedText<V: View>(_ view: V) throws -> String {
        window?.close()
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_024, height: 700)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.setContentSize(hostingView.frame.size)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        self.window = window

        // This DEBUG-only verifier captures only its own window. The legacy API
        // avoids prompting developers for Screen Recording permission in tests.
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming]
        ) else {
            throw AppShellVerificationError.couldNotCapture
        }
        return try recognizeText(in: image)
    }

    func use(_ snapshot: WorkbenchSnapshot) {
        model.replaceTestingSnapshot(snapshot)
    }

    func close() {
        window?.close()
        try? FileManager.default.removeItem(at: supportDirectory)
    }
}

private enum AppShellVerificationError: Error {
    case couldNotCapture
    case failed([String])
}

private func recognizeText(in image: CGImage) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: image)
    try handler.perform([request])
    return (request.results ?? [])
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
}
#endif
