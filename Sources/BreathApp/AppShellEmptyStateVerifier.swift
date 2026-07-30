#if DEBUG
import AppKit
import ApplicationServices
import BreathAutomation
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
        let canInspectAccessibility = AXIsProcessTrusted()

        var visibleText = try fixture.renderedText(WorkbenchView(model: fixture.model))
        var canvasInspection = try fixture.inspectBlankTerminalCanvas()
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
        if canInspectAccessibility {
            let accessibilityText = fixture.accessibilityText()
            require(
                !accessibilityText.contains("还没有工作区")
                    && !accessibilityText.contains("添加一个项目目录以打开第一个空终端"),
                "removed workspace prompt remains in the accessibility tree: \(accessibilityText)",
                into: &failures
            )
            require(
                !accessibilityText.contains("选择一个工作会话")
                    && !accessibilityText.contains("只会在选中时恢复对应布局"),
                "removed selection prompt remains in the accessibility tree: \(accessibilityText)",
                into: &failures
            )
            require(
                accessibilityText.contains(WorkbenchAccessibility.addWorkspace),
                "add workspace action lost its accessibility label: \(accessibilityText)",
                into: &failures
            )
            require(
                accessibilityText.contains(WorkbenchAccessibility.noSelectedWorkSession),
                "blank terminal canvas lost its accessibility status: \(accessibilityText)",
                into: &failures
            )
            require(
                accessibilityText.contains(WorkbenchAccessibility.openWorkspace),
                "activity bar workspace action lost its accessibility label: \(accessibilityText)",
                into: &failures
            )
            require(
                accessibilityText.contains(WorkbenchAccessibility.openSettings),
                "activity bar settings action lost its accessibility label: \(accessibilityText)",
                into: &failures
            )
            require(
                accessibilityText.contains(WorkbenchAccessibility.openAutomation),
                "activity bar automation action lost its accessibility label: \(accessibilityText)",
                into: &failures
            )
            require(
                fixture.pressAccessibilityElement(named: WorkbenchAccessibility.openAutomation),
                "activity bar automation action could not be pressed through accessibility",
                into: &failures
            )
            let automationAccessibilityText = fixture.accessibilityText()
            require(
                automationAccessibilityText.contains(
                    WorkbenchAccessibility.automationPanel
                ),
                "automation action did not open the automation panel",
                into: &failures
            )
            require(
                !automationAccessibilityText.contains(
                    WorkbenchAccessibility.addWorkspace
                ),
                "workspace sidebar remained visible beside the automation page",
                into: &failures
            )
            let automationSearchFrame = fixture.accessibilityFrame(
                named: AutomationAccessibility.search
            )
            let automationCreateFrame = fixture.accessibilityFrame(
                named: AutomationAccessibility.create
            )
            require(
                automationSearchFrame.flatMap { searchFrame in
                    automationCreateFrame.map { createFrame in
                        abs(searchFrame.midY - createFrame.midY) < 160
                    }
                } == true,
                "the Automation list collapsed away from the top toolbar",
                into: &failures
            )
            require(
                automationAccessibilityText.contains("尚未创建自动化"),
                "the empty Automation library lost its compact empty state",
                into: &failures
            )
            require(
                fixture.accessibilityElementSupportsPress(
                    named: AutomationAccessibility.create
                ),
                "Automation creation was disabled without a Workspace",
                into: &failures
            )
            require(
                fixture.pressAccessibilityElement(
                    named: WorkbenchAccessibility.openWorkspace
                ),
                "activity bar workspace action could not be pressed through accessibility",
                into: &failures
            )
            require(
                fixture.accessibilityText().contains(
                    WorkbenchAccessibility.addWorkspace
                ),
                "workspace action did not restore the workspace sidebar",
                into: &failures
            )
        }
        require(
            fixture.terminalLaunchCount == 0,
            "rendering the empty workbench launched a terminal",
            into: &failures
        )
        require(
            !canvasInspection.isSolid,
            "empty terminal canvas lost its compact empty state: \(canvasInspection)",
            into: &failures
        )
        let automationVerificationProbe = AutomationViewVerificationProbe()
        let emptyAutomationFixture = try AppShellFixture(snapshot: .empty)
        defer { emptyAutomationFixture.close() }
        let emptyAutomationText = try emptyAutomationFixture.renderedText(
            AutomationView(
                model: emptyAutomationFixture.model,
                verificationProbe: automationVerificationProbe
            ),
            size: NSSize(width: 1_024, height: 700)
        )
        require(
            emptyAutomationText.contains("新建自动化"),
            "the empty Automation page lost its creation action",
            into: &failures
        )
        require(
            emptyAutomationText.contains("尚未创建自动化"),
            "the empty Automation page lost its compact empty state",
            into: &failures
        )
        require(
            emptyAutomationFixture.capturedColorsMatch(
                at: CGPoint(x: 0.25, y: 0.55),
                and: CGPoint(x: 0.75, y: 0.55)
            ),
            "the empty Automation list rendered an opaque sidebar background",
            into: &failures
        )
        require(
            automationVerificationProbe.presentCreationEditor(),
            "the empty Automation creation action was not available",
            into: &failures
        )
        require(
            automationVerificationProbe.isCreationEditorPresented,
            "the empty Automation creation action did not request the editor",
            into: &failures
        )
        require(
            automationVerificationProbe.dismissCreationEditor(),
            "the Automation editor presentation could not be reset",
            into: &failures
        )
        require(
            !automationVerificationProbe.isCreationEditorPresented,
            "the Automation editor presentation remained active",
            into: &failures
        )
        let automationEditorText = try emptyAutomationFixture.renderedText(
            automationEditorVerificationView(
                model: emptyAutomationFixture.model,
                probe: automationVerificationProbe
            ),
            size: NSSize(width: 640, height: 700)
        )
        require(
            automationEditorText.contains("所属工作区")
                && automationEditorText.contains("没有可选工作区")
                && automationEditorText.contains("未命名"),
            "the real Automation editor lost its localized defaults: \(automationEditorText)",
            into: &failures
        )
        require(
            !automationEditorText.contains(
                "所选 Agent 当前不可用于自动化。"
            ),
            "the Automation editor marked an available Agent as unavailable",
            into: &failures
        )
        require(
            automationVerificationProbe.workspaceAccessExplanation
                == "Agent 直接读取真实工作区，但 macOS 沙盒会阻止它修改项目文件。",
            "the Automation editor lost its Workspace-access explanation",
            into: &failures
        )
        require(
            automationVerificationProbe.cancelEditor(),
            "the Automation editor dismiss action was not available",
            into: &failures
        )
        require(
            automationVerificationProbe.didCancelEditor,
            "the Automation editor dismiss action did not run",
            into: &failures
        )

        let activeWorkSessionSnapshot = makeSnapshotWithActiveWorkSession()
        try fixture.use(activeWorkSessionSnapshot)
        visibleText = try fixture.renderedText(WorkbenchView(model: fixture.model))
        canvasInspection = try fixture.inspectBlankTerminalCanvas()
        require(visibleText.contains("示例项目"), "workspace tree did not render", into: &failures)
        if canInspectAccessibility {
            require(
                fixture.expandDisclosure(named: "示例项目"),
                "workspace disclosure could not be expanded through accessibility",
                into: &failures
            )
            require(
                fixture.accessibilityText().contains("Agent 对话摘要"),
                "active WorkSession tree content did not render",
                into: &failures
            )
        }
        require(!visibleText.contains("选择一个工作会话"), "selection title is visible with a workspace", into: &failures)
        require(
            fixture.model.snapshot == activeWorkSessionSnapshot,
            "rendering changed the active WorkSession snapshot",
            into: &failures
        )
        require(
            fixture.terminalLaunchCount == 0,
            "rendering an unselected WorkSession launched a terminal",
            into: &failures
        )
        require(
            !canvasInspection.isSolid,
            "unselected WorkSession canvas lost its compact empty state: \(canvasInspection)",
            into: &failures
        )

        let selectedTabsSnapshot = makeSnapshotWithSelectedWorkSessionTabs()
        try fixture.use(selectedTabsSnapshot)
        visibleText = try fixture.renderedText(WorkbenchView(model: fixture.model))
        let tabAccessibilityText = canInspectAccessibility
            ? fixture.accessibilityText()
            : []
        require(
            visibleText.contains("实现会话") && visibleText.contains("审查会话"),
            "same-workspace WorkSessions did not render as visible tabs: \(visibleText)",
            into: &failures
        )
        if canInspectAccessibility {
            require(
                tabAccessibilityText.contains(where: { $0.contains("实现会话") })
                    && tabAccessibilityText.contains(where: { $0.contains("审查会话") }),
                "WorkSession tabs are missing from the accessibility tree: \(tabAccessibilityText)",
                into: &failures
            )
        }
        require(
            fixture.model.snapshot == selectedTabsSnapshot,
            "rendering WorkSession tabs changed the snapshot",
            into: &failures
        )
        require(
            fixture.terminalLaunchCount == 0,
            "rendering WorkSession tabs launched a terminal",
            into: &failures
        )

        let workspaceID = WorkspaceID(rawValue: UUID())
        let noWorkSessionsSnapshot = WorkbenchSnapshot(
            workspaces: [Workspace(id: workspaceID, path: "/tmp", displayName: "空项目")],
            workSessions: [],
            selectedWorkSessionID: nil
        )
        try fixture.use(noWorkSessionsSnapshot)
        visibleText = try fixture.renderedText(WorkbenchView(model: fixture.model))
        canvasInspection = try fixture.inspectBlankTerminalCanvas()
        require(visibleText.contains("空项目"), "workspace without sessions did not render", into: &failures)
        require(!visibleText.contains("选择一个工作会话"), "selection title is visible without sessions", into: &failures)
        require(
            fixture.model.snapshot == noWorkSessionsSnapshot,
            "rendering created or selected a WorkSession",
            into: &failures
        )
        require(
            fixture.terminalLaunchCount == 0,
            "rendering a workspace without WorkSessions launched a terminal",
            into: &failures
        )
        require(
            !canvasInspection.isSolid,
            "empty WorkSession canvas lost its compact empty state: \(canvasInspection)",
            into: &failures
        )

        let automationSnapshot = makeAutomationSnapshot(
            workspace: noWorkSessionsSnapshot.workspaces[0]
        )
        try fixture.use(
            noWorkSessionsSnapshot,
            automationSnapshot: automationSnapshot
        )
        let automationWideText = try fixture.renderedText(
            AutomationView(model: fixture.model)
        )
        require(
            automationWideText.contains("检查依赖边界")
                && automationWideText.contains("最近运行")
                && automationWideText.contains("成功"),
            "wide automation library did not render its list and detail: \(automationWideText)",
            into: &failures
        )
        let automationSampleAccessibilityText = canInspectAccessibility
            ? fixture.accessibilityText()
            : []
        if canInspectAccessibility {
            require(
                automationSampleAccessibilityText.contains(
                    AutomationAccessibility.panel
                )
                    && automationSampleAccessibilityText.contains(
                        AutomationAccessibility.search
                    ),
                "automation page lost its accessibility structure: \(automationSampleAccessibilityText)",
                into: &failures
            )
        }
        let automationCompactText = try fixture.renderedText(
            AutomationView(model: fixture.model),
            size: NSSize(width: 680, height: 700)
        )
        require(
            automationCompactText.contains("检查模块依赖"),
            "compact automation library did not keep its navigation list readable: \(automationCompactText)",
            into: &failures
        )
        require(
            fixture.terminalLaunchCount == 0,
            "rendering Automation launched a terminal",
            into: &failures
        )

        let settingsText = try fixture.renderedText(
            BreathSettingsView(model: fixture.model, selectedTab: .archives)
        )
        require(settingsText.contains("已归档"), "archived settings tab did not render", into: &failures)
        require(!settingsText.contains("没有已归档会话"), "archived settings still use the large empty title", into: &failures)
        require(
            fixture.terminalLaunchCount == 0,
            "rendering archived settings launched a terminal",
            into: &failures
        )

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

    private static func makeSnapshotWithActiveWorkSession() -> WorkbenchSnapshot {
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

    private static func makeSnapshotWithSelectedWorkSessionTabs() -> WorkbenchSnapshot {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let selectedSessionID = WorkSessionID(rawValue: UUID())
        return WorkbenchSnapshot(
            workspaces: [Workspace(id: workspaceID, path: "/tmp", displayName: "示例项目")],
            workSessions: [
                WorkSession(
                    id: selectedSessionID,
                    workspaceID: workspaceID,
                    title: "实现会话",
                    pane: TerminalPane(id: TerminalPaneID(rawValue: UUID())),
                    titleSource: .agentNative
                ),
                WorkSession(
                    id: WorkSessionID(rawValue: UUID()),
                    workspaceID: workspaceID,
                    title: "审查会话",
                    pane: TerminalPane(id: TerminalPaneID(rawValue: UUID())),
                    titleSource: .agentNative
                ),
            ],
            selectedWorkSessionID: selectedSessionID
        )
    }

    private static func makeAutomationSnapshot(
        workspace: Workspace
    ) -> AutomationSnapshot {
        let automationID = AutomationID(rawValue: UUID())
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        return AutomationSnapshot(
            automations: [
                Automation(
                    id: automationID,
                    name: "检查依赖边界",
                    workspaceID: workspace.id,
                    workspaceDisplayName: workspace.displayName,
                    workspacePath: workspace.path,
                    prompt: "检查模块依赖，并给出需要优先处理的风险。",
                    agent: .codex,
                    trigger: .cron("0 9 * * 1-5"),
                    maximumDurationMinutes: 60,
                    isEnabled: true,
                    createdAt: timestamp,
                    updatedAt: timestamp
                ),
            ],
            runs: [
                AutomationRun(
                    id: AutomationRunID(rawValue: UUID()),
                    automationID: automationID,
                    status: .succeeded,
                    triggerSource: .scheduled,
                    queuedAt: timestamp,
                    startedAt: timestamp,
                    endedAt: timestamp.addingTimeInterval(8),
                    effectiveDuration: 8,
                    agent: .codex,
                    model: "gpt-5",
                    finalOutput: "# 项目检查\n\n依赖边界清晰。",
                    isViewed: false
                ),
            ],
            concurrencyLimit: 2
        )
    }
}

@MainActor
private final class AppShellFixture {
    private var harness: AppShellTestingHarness
    private let supportDirectory: URL
    private var window: NSWindow?
    private var capturedImage: CGImage?

    var model: BreathApplicationModel {
        harness.model
    }

    var terminalLaunchCount: Int {
        harness.terminalEngine.openedLaunches.count
    }

    init(snapshot: WorkbenchSnapshot) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("breath-app-shell-\(UUID().uuidString)", isDirectory: true)
        harness = try AppShellTestingHarness(
            snapshot: snapshot,
            supportDirectory: supportDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
    }

    func renderedText<V: View>(
        _ view: V,
        size: NSSize = NSSize(width: 1_024, height: 700)
    ) throws -> String {
        window?.close()
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
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
        NSAccessibility.post(
            element: hostingView,
            notification: .layoutChanged
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        self.window = window

        // Render the verifier's own view directly. Screen capture APIs are both
        // unnecessary here and liable to request Screen Recording permission.
        let captureBounds = hostingView.bounds
        guard !captureBounds.isEmpty,
              let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: captureBounds)
        else {
            throw AppShellVerificationError.couldNotCapture
        }
        hostingView.cacheDisplay(in: captureBounds, to: bitmap)
        guard let image = bitmap.cgImage else {
            throw AppShellVerificationError.couldNotCapture
        }
        capturedImage = image
        return try recognizeText(in: image)
    }

    func capturedColorsMatch(
        at firstPoint: CGPoint,
        and secondPoint: CGPoint,
        tolerance: Int = 6
    ) -> Bool {
        guard let image = capturedImage,
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else {
            return false
        }
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        guard bytesPerPixel >= 3 else { return false }

        func offset(for point: CGPoint) -> Int {
            let x = min(
                image.width - 1,
                max(0, Int(point.x * CGFloat(image.width)))
            )
            let y = min(
                image.height - 1,
                max(0, Int(point.y * CGFloat(image.height)))
            )
            return y * image.bytesPerRow + x * bytesPerPixel
        }

        let firstOffset = offset(for: firstPoint)
        let secondOffset = offset(for: secondPoint)
        return (0..<3).allSatisfy { component in
            abs(
                Int(bytes[firstOffset + component])
                    - Int(bytes[secondOffset + component])
            ) <= tolerance
        }
    }

    func inspectBlankTerminalCanvas() throws -> SolidCanvasInspection {
        guard let capturedImage else {
            throw AppShellVerificationError.couldNotCapture
        }
        return try SolidCanvasInspection(
            image: capturedImage,
            background: model.effectiveTerminalColorTheme.palette.background
        )
    }

    func use(
        _ snapshot: WorkbenchSnapshot,
        automationSnapshot: AutomationSnapshot = .empty
    ) throws {
        window?.close()
        harness = try AppShellTestingHarness(
            snapshot: snapshot,
            automationSnapshot: automationSnapshot,
            supportDirectory: supportDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
    }

    func accessibilityText() -> [String] {
        let application = AXUIElementCreateApplication(
            ProcessInfo.processInfo.processIdentifier
        )
        var visited: [AXUIElement] = []
        return accessibilityText(
            in: application,
            depth: 0,
            visited: &visited
        )
    }

    func expandDisclosure(named name: String) -> Bool {
        pressAccessibilityElement(named: name)
    }

    func pressAccessibilityElement(named name: String) -> Bool {
        let application = AXUIElementCreateApplication(
            ProcessInfo.processInfo.processIdentifier
        )
        var visited: [AXUIElement] = []
        guard pressAccessibilityElement(
            named: name,
            in: application,
            depth: 0,
            visited: &visited
        ) else {
            return false
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        window?.layoutIfNeeded()
        return true
    }

    func accessibilityElementSupportsPress(named name: String) -> Bool {
        guard let element = accessibilityElement(named: name) else {
            return false
        }
        return pressTarget(for: element) != nil
    }

    func accessibilityFrame(named name: String) -> CGRect? {
        guard let element = accessibilityElement(named: name) else {
            return nil
        }
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
            AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &sizeValue
            ) == .success,
            let positionValue,
            let sizeValue,
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(
            positionValue as! AXValue,
            .cgPoint,
            &position
        ),
            AXValueGetValue(
                sizeValue as! AXValue,
                .cgSize,
                &size
            )
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func accessibilityElement(named name: String) -> AXUIElement? {
        let application = AXUIElementCreateApplication(
            ProcessInfo.processInfo.processIdentifier
        )
        var visited: [AXUIElement] = []
        return accessibilityElement(
            named: name,
            in: application,
            depth: 0,
            visited: &visited
        )
    }

    func close() {
        window?.close()
        try? FileManager.default.removeItem(at: supportDirectory)
    }

    private func accessibilityText(
        in element: AXUIElement,
        depth: Int,
        visited: inout [AXUIElement]
    ) -> [String] {
        guard depth < 20,
              !visited.contains(where: { CFEqual($0, element) })
        else {
            return []
        }
        visited.append(element)
        var text = accessibilityStrings(for: element)
        for child in accessibilityChildren(of: element) {
            text.append(
                contentsOf: accessibilityText(
                    in: child,
                    depth: depth + 1,
                    visited: &visited
                )
            )
        }
        return text
    }

    private func accessibilityStrings(for element: AXUIElement) -> [String] {
        var text: [String] = []
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
               let string = value as? String,
               !string.isEmpty {
                text.append(string)
            }
        }
        return text
    }

    private func accessibilityChildren(of element: AXUIElement) -> [AXUIElement] {
        var children: [AXUIElement] = []
        for attribute in [kAXWindowsAttribute, kAXChildrenAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let attributeChildren = value as? [AXUIElement]
            else {
                continue
            }
            children.append(contentsOf: attributeChildren)
        }
        return children
    }

    private func accessibilityElement(
        named name: String,
        in element: AXUIElement,
        depth: Int,
        visited: inout [AXUIElement]
    ) -> AXUIElement? {
        guard depth < 20,
              !visited.contains(where: { CFEqual($0, element) })
        else {
            return nil
        }
        visited.append(element)
        if accessibilityStrings(for: element).contains(name) {
            return element
        }
        for child in accessibilityChildren(of: element) {
            if let match = accessibilityElement(
                named: name,
                in: child,
                depth: depth + 1,
                visited: &visited
            ) {
                return match
            }
        }
        return nil
    }

    private func pressAccessibilityElement(
        named name: String,
        in element: AXUIElement,
        depth: Int,
        visited: inout [AXUIElement]
    ) -> Bool {
        guard depth < 20,
              !visited.contains(where: { CFEqual($0, element) })
        else {
            return false
        }
        visited.append(element)
        if accessibilityStrings(for: element).contains(name),
           pressElementOrAncestor(element) {
            return true
        }
        return accessibilityChildren(of: element).contains { child in
            pressAccessibilityElement(
                named: name,
                in: child,
                depth: depth + 1,
                visited: &visited
            )
        }
    }

    private func pressElementOrAncestor(_ element: AXUIElement) -> Bool {
        guard let target = pressTarget(for: element) else {
            return false
        }
        return AXUIElementPerformAction(
            target,
            kAXPressAction as CFString
        ) == .success
    }

    private func pressTarget(for element: AXUIElement) -> AXUIElement? {
        var candidate = element
        for _ in 0..<6 {
            var actionNames: CFArray?
            if AXUIElementCopyActionNames(candidate, &actionNames) == .success,
               let actionNames = actionNames as? [String],
               actionNames.contains(kAXPressAction)
            {
                return candidate
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                candidate,
                kAXParentAttribute as CFString,
                &parent
            ) == .success,
                let parent,
                CFGetTypeID(parent) == AXUIElementGetTypeID()
            else {
                return nil
            }
            candidate = parent as! AXUIElement
        }
        return nil
    }
}

private enum AppShellVerificationError: Error {
    case couldNotCapture
    case couldNotReadPixels
    case failed([String])
}

struct SolidCanvasInspection: CustomStringConvertible {
    let regionPixels: Int
    let boundingPixels: Int
    let enclosedPixels: Int
    let imagePixels: Int

    var isSolid: Bool {
        enclosedPixels == 0 && boundingPixels * 2 > imagePixels
    }

    var description: String {
        "region=\(regionPixels), bounds=\(boundingPixels), enclosed=\(enclosedPixels), image=\(imagePixels)"
    }

    init(image: CGImage, background: TerminalRGBColor) throws {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let rendered = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw AppShellVerificationError.couldNotReadPixels }

        let target = (background.red, background.green, background.blue)
        func isBackground(_ index: Int) -> Bool {
            let offset = index * 4
            return abs(Int(pixels[offset]) - Int(target.0)) <= 1
                && abs(Int(pixels[offset + 1]) - Int(target.1)) <= 1
                && abs(Int(pixels[offset + 2]) - Int(target.2)) <= 1
                && pixels[offset + 3] > 0
        }

        var visited = [Bool](repeating: false, count: width * height)
        var largest = (count: 0, minX: 0, maxX: -1, minY: 0, maxY: -1)
        for index in 0..<visited.count where !visited[index] && isBackground(index) {
            var stack = [index]
            visited[index] = true
            var region = (
                count: 0,
                minX: index % width,
                maxX: index % width,
                minY: index / width,
                maxY: index / width
            )
            while let current = stack.popLast() {
                let x = current % width
                let y = current / width
                region.count += 1
                region.minX = min(region.minX, x)
                region.maxX = max(region.maxX, x)
                region.minY = min(region.minY, y)
                region.maxY = max(region.maxY, y)
                for neighbor in [
                    x > 0 ? current - 1 : -1,
                    x + 1 < width ? current + 1 : -1,
                    y > 0 ? current - width : -1,
                    y + 1 < height ? current + width : -1,
                ] where neighbor >= 0 && !visited[neighbor] && isBackground(neighbor) {
                    visited[neighbor] = true
                    stack.append(neighbor)
                }
            }
            if region.count > largest.count {
                largest = region
            }
        }

        regionPixels = largest.count
        let boundsWidth = max(0, largest.maxX - largest.minX + 1)
        let boundsHeight = max(0, largest.maxY - largest.minY + 1)
        boundingPixels = boundsWidth * boundsHeight
        imagePixels = width * height

        var boundaryConnected = [Bool](repeating: false, count: boundingPixels)
        var boundaryStack: [Int] = []
        if boundsWidth > 0, boundsHeight > 0 {
            for localY in 0..<boundsHeight {
                for localX in 0..<boundsWidth
                where localX == 0 || localX == boundsWidth - 1
                    || localY == 0 || localY == boundsHeight - 1 {
                    let localIndex = localY * boundsWidth + localX
                    let imageIndex = (largest.minY + localY) * width + largest.minX + localX
                    if !isBackground(imageIndex), !boundaryConnected[localIndex] {
                        boundaryConnected[localIndex] = true
                        boundaryStack.append(localIndex)
                    }
                }
            }
        }
        while let current = boundaryStack.popLast() {
            let x = current % boundsWidth
            let y = current / boundsWidth
            for neighbor in [
                x > 0 ? current - 1 : -1,
                x + 1 < boundsWidth ? current + 1 : -1,
                y > 0 ? current - boundsWidth : -1,
                y + 1 < boundsHeight ? current + boundsWidth : -1,
            ] where neighbor >= 0 && !boundaryConnected[neighbor] {
                let imageX = largest.minX + neighbor % boundsWidth
                let imageY = largest.minY + neighbor / boundsWidth
                if !isBackground(imageY * width + imageX) {
                    boundaryConnected[neighbor] = true
                    boundaryStack.append(neighbor)
                }
            }
        }
        enclosedPixels = boundaryConnected.indices.reduce(into: 0) { count, localIndex in
            guard !boundaryConnected[localIndex] else { return }
            let imageX = largest.minX + localIndex % boundsWidth
            let imageY = largest.minY + localIndex / boundsWidth
            if !isBackground(imageY * width + imageX) {
                count += 1
            }
        }
    }
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
