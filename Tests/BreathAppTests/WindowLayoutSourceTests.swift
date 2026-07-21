import AppKit
import Foundation
import SwiftUI
import Testing
@testable import BreathApp

@MainActor
private final class TestSplitTrackingAncestor:
    NSView,
    SplitDividerTrackingState
{
    var isTrackingDividerForDescendants = false
}

@Suite("Main window layout source guard")
struct WindowLayoutSourceTests {
    @Test("global Skills stays reachable beside Tasks without a selected workspace")
    func globalSkillsNavigationIsIndependent() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("case skills"))
        #expect(source.contains("WorkbenchAccessibility.openSkills"))
        #expect(source.contains("SkillsView(service: model.skillsService"))
        let tasks = try #require(source.range(of: "WorkbenchAccessibility.openTaskView"))
        let skills = try #require(source.range(of: "WorkbenchAccessibility.openSkills"))
        #expect(tasks.lowerBound < skills.lowerBound)

        let skillsSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/SkillsView.swift"),
            encoding: .utf8
        )
        #expect(skillsSource.contains("NSApplication.didBecomeActiveNotification"))
        #expect(skillsSource.contains("GeometryReader"))
        #expect(skillsSource.contains("NavigationStack"))
        #expect(skillsSource.contains("NavigationLink(value: skill.id)"))
        #expect(skillsSource.contains("HSplitView"))
        #expect(!skillsSource.contains("NavigationSplitView"))
        #expect(!skillsSource.contains("sidebarToggle"))
        #expect(skillsSource.contains("private var listControls: some View"))
        #expect(skillsSource.contains(".menuStyle(.borderlessButton)"))
        #expect(skillsSource.contains("Image(systemName: \"arrow.clockwise\")"))
        #expect(skillsSource.contains("private var listBackground: Color"))
        #expect(skillsSource.contains(".scrollContentBackground(.hidden)"))
        #expect(skillsSource.contains(".padding(.top, 6)"))
        #expect(!skillsSource.contains("skill.sourceKinds"))
        #expect(!skillsSource.contains("copy.repository"))
        #expect(!skillsSource.contains("model.selectedSource"))
        #expect(skillsSource.contains("localizer.format(\"作者：%@\", author)"))
        #expect(skillsSource.contains(".accessibilityLabel(accessibilityLabel)"))
        #expect(!skillsSource.contains(
            "Label(localizer.string(\"刷新\"), systemImage: \"arrow.clockwise\")"
        ))

        let headerStart = try #require(
            skillsSource.range(of: "private var header: some View")
        )
        let listControlsStart = try #require(
            skillsSource.range(of: "private var listControls: some View")
        )
        let headerSource = skillsSource[
            headerStart.lowerBound..<listControlsStart.lowerBound
        ]
        #expect(!headerSource.contains("TextField"))
        #expect(!headerSource.contains("filterMenu"))
        #expect(!headerSource.contains("model.refresh()"))
        #expect(headerSource.contains(
            "HStack(alignment: .firstTextBaseline, spacing: 8)"
        ))
        #expect(headerSource.contains(".font(.title2.weight(.semibold))"))
        #expect(headerSource.contains("WorkbenchLayout.windowControlsHeight"))
        #expect(headerSource.contains("WorkbenchLayout.sidebarHeaderRowHeight"))
        #expect(!headerSource.contains("WorkbenchLayout.sidebarHeaderVerticalPadding"))
        #expect(!headerSource.contains("VStack(alignment: .leading"))
        #expect(!headerSource.contains(".padding(.top, 32)"))

        let serviceSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathSkills/BreathSkills.swift"),
            encoding: .utf8
        )
        #expect(serviceSource.contains("SkillDirectoryEventMonitor"))
        #expect(!serviceSource.contains("every interval: Duration = .seconds(1)"))
        let managementSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/BreathApp/SkillManagementSheets.swift"
            ),
            encoding: .utf8
        )
        #expect(managementSource.contains("ForEach(item.candidate.warnings)"))
        #expect(managementSource.contains("RiskBadge(audit: item.securityAudit"))
        #expect(managementSource.contains("item.securityAudit.checkedAt"))
        #expect(managementSource.contains("confirmedRiskCandidateIDs"))
        #expect(managementSource.contains("confirmedRiskCandidateIDs: confirmedRiskCandidateIDs"))
    }

    @Test("Skill installer uses compact explicit source tabs and inline source errors")
    func skillInstallerSourceSelectionStaysCompact() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/BreathApp/SkillManagementSheets.swift"
            ),
            encoding: .utf8
        )
        let sourceStepStart = try #require(
            source.range(of: "private var sourceStep: some View")
        )
        let candidateStepStart = try #require(
            source.range(
                of: "private var candidateStep: some View",
                range: sourceStepStart.upperBound..<source.endIndex
            )
        )
        let sourceStep = source[
            sourceStepStart.lowerBound..<candidateStepStart.lowerBound
        ]

        let skillsShTab = try #require(
            sourceStep.range(of: "Text(\"skills.sh\").tag(SourceMode.skillsSh)")
        )
        let githubTab = try #require(
            sourceStep.range(of: "Text(\"GitHub\").tag(SourceMode.github)")
        )
        let zipTab = try #require(
            sourceStep.range(of: "Text(\"ZIP\").tag(SourceMode.zip)")
        )
        #expect(skillsShTab.lowerBound < githubTab.lowerBound)
        #expect(githubTab.lowerBound < zipTab.lowerBound)
        #expect(!sourceStep.contains("ContentUnavailableView"))
        #expect(sourceStep.contains("sourceMessage"))
        #expect(sourceStep.contains(
            ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"
        ))
        #expect(sourceStep.contains(
            "Button(localizer.string(\"安装\"), action: resolveGitHubInput)"
        ))
        #expect(sourceStep.contains("isInstalled ? \"安装到其他 Agent\" : \"安装\""))
        #expect(sourceStep.contains(
            "isInstalled ? \"将 %@ 安装到其他 Agent\" : \"安装 %@\""
        ))
        #expect(!sourceStep.contains("Text(item.source)"))
        #expect(sourceStep.contains("installedCopies(matching: item)"))
        #expect(sourceStep.contains("installedAgentNames(in: installedCopies)"))
        #expect(sourceStep.contains("$0.matchesSkillsShCatalogEntry(item)"))
        #expect(sourceStep.contains("localizer.format(\"提交者：%@\", submitter)"))
        #expect(sourceStep.contains("已安装于 %@"))
        #expect(!sourceStep.contains(".filter { $0.name == name }"))
        #expect(sourceStep.contains(".task(id: skillsShInput)"))
        #expect(sourceStep.contains("searchSkillsShAfterDebounce"))
        #expect(!sourceStep.contains("Button(localizer.string(\"搜索\")"))
        #expect(!sourceStep.contains("localizer.string(\"暂无说明\")"))
        #expect(!sourceStep.contains(".onSubmit(resolveGitHubInput)"))
        #expect(sourceStep.contains("activity == .downloadingCatalog(item.id)"))
        #expect(sourceStep.contains("activity == .preparingInstalledCopy(item.id)"))
        #expect(sourceStep.contains("fromInstalledCopy: sourceCopy"))
        #expect(sourceStep.contains("nextStep: .targets"))
        #expect(!sourceStep.contains("管理安装…"))
        #expect(sourceStep.contains("activity == .downloadingGitHub"))
        #expect(sourceStep.contains("localizer.string(\"正在下载…\")"))
        #expect(!sourceStep.contains("Image(systemName: \"chevron.right\")"))
        #expect(source.contains("private func resolveGitHubInput()"))
        #expect(source.contains("private func searchSkillsShAfterDebounce() async"))
        #expect(!source.contains("resolveOnlineInput"))
        #expect(!source.contains("case online"))
        let updateViewStart = try #require(
            source.range(of: "struct SkillUpdateReviewView: View")
        )
        let installer = source[..<updateViewStart.lowerBound]
        #expect(!installer.contains(".alert(\"Breath\""))
        #expect(installer.contains("localizedSourceMessage(for: error)"))
        #expect(!installer.contains("skills.sh 当前无法从 Breath 搜索"))
        #expect(!installer.contains("@State private var isWorking"))
        #expect(installer.contains("private var isWorking: Bool { activity != nil }"))
        #expect(installer.contains("progressStatus(\"正在安装…\")"))
        #expect(installer.contains("existingMatch.displayName(localizer)"))
        #expect(installer.contains("localizer.string(\"安装状态\")"))

        let guidelines = try String(
            contentsOf: root.appendingPathComponent(
                "docs/design/interface-guidelines.md"
            ),
            encoding: .utf8
        )
        #expect(guidelines.contains("流程页面不得使用超大提示标题"))
        #expect(guidelines.contains("ContentUnavailableView"))
        #expect(guidelines.contains("下载内容或写入磁盘"))
        #expect(guidelines.contains("安装预览"))
        #expect(guidelines.contains("不得使用导航箭头"))
    }

    @Test("DEBUG app shell verifier captures its own view without deprecated screen APIs")
    func appShellVerifierAvoidsDeprecatedScreenCapture() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/BreathApp/AppShellEmptyStateVerifier.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains("CGWindowListCreateImage"))
        #expect(source.contains("bitmapImageRepForCachingDisplay"))
        #expect(source.contains("cacheDisplay(in: captureBounds, to: bitmap)"))
    }

    @Test("Git error alerts keep long command output compact")
    func gitErrorPresentationIsBounded() {
        let longOutput = (1...80)
            .map { "create mode 100644 file-\($0).md" }
            .joined(separator: "\n")
        let notice = "Full output is available in Git Console."
        let summary = GitErrorPresentation.summary(
            longOutput,
            truncationNotice: notice
        )

        #expect(summary.count <= 900)
        #expect(summary.contains("file-1.md"))
        #expect(!summary.contains("file-80.md"))
        #expect(summary.contains(notice))
        #expect(
            GitErrorPresentation.summary(
                "fatal: remote rejected",
                truncationNotice: notice
            ) == "fatal: remote rejected"
        )
    }

    @Test("Git three-column split keeps the second divider fixed while moving the first")
    @MainActor
    func gitThreeColumnDividersResizeIndependently() {
        let splitView = GitThreeColumnNSView(
            frame: NSRect(x: 0, y: 0, width: 1_000, height: 500)
        )
        splitView.setContent(
            left: AnyView(Color.clear),
            center: AnyView(Color.clear),
            right: AnyView(Color.clear)
        )
        splitView.configure(
            leftWidth: 250,
            centerWidth: 300,
            onResizeEnded: nil,
            appliesPosition: true
        )
        splitView.layoutSubtreeIfNeeded()
        splitView.updateTrackingAreas()

        let secondDividerBefore = splitView.arrangedSubviews[1].frame.maxX
        let firstDividerBefore = splitView.arrangedSubviews[0].frame.maxX
        #expect(
            splitView.trackingAreas.filter {
                $0.options.contains(.cursorUpdate)
                    && $0.options.contains(.enabledDuringMouseDrag)
            }.count == 2
        )
        #expect(
            splitView.hitTest(
                NSPoint(x: firstDividerBefore, y: 100)
            ) === splitView
        )
        splitView.setPosition(300, ofDividerAt: 0)
        let secondDividerAfter = splitView.arrangedSubviews[1].frame.maxX

        #expect(abs(secondDividerAfter - secondDividerBefore) < 0.5)
        #expect(abs(splitView.arrangedSubviews[0].frame.width - 300) < 0.5)
        #expect(abs(splitView.arrangedSubviews[1].frame.width - 250) < 0.5)
        #expect(
            splitView.arrangedSubviews[0].frame.maxX
                < splitView.arrangedSubviews[1].frame.minX
        )
        #expect(
            splitView.arrangedSubviews[1].frame.maxX
                < splitView.arrangedSubviews[2].frame.minX
        )
    }

    @Test("Git three-column split remains non-overlapping when its parent width changes")
    @MainActor
    func gitThreeColumnRelayoutsAfterParentResize() {
        let splitView = GitThreeColumnNSView(
            frame: NSRect(x: 0, y: 0, width: 1_500, height: 700)
        )
        splitView.setContent(
            left: AnyView(Color.clear),
            center: AnyView(Color.clear),
            right: AnyView(Color.clear)
        )
        splitView.configure(
            leftWidth: 380,
            centerWidth: 430,
            onResizeEnded: nil,
            appliesPosition: true
        )
        splitView.layoutSubtreeIfNeeded()

        splitView.setFrameSize(NSSize(width: 1_050, height: 700))
        splitView.layoutSubtreeIfNeeded()

        let panes = splitView.arrangedSubviews
        #expect(panes[0].frame.minX == splitView.bounds.minX)
        #expect(panes[0].frame.maxX < panes[1].frame.minX)
        #expect(panes[1].frame.maxX < panes[2].frame.minX)
        #expect(panes[2].frame.maxX <= splitView.bounds.maxX + 0.5)
        #expect(panes.allSatisfy { $0.frame.width >= 0 })
    }

    @Test("Git columns defer relayout while an ancestor divider is tracking")
    @MainActor
    func gitThreeColumnDefersAncestorDragUpdates() {
        let ancestor = TestSplitTrackingAncestor(
            frame: NSRect(x: 0, y: 0, width: 1_100, height: 700)
        )
        let splitView = GitThreeColumnNSView(frame: ancestor.bounds)
        ancestor.addSubview(splitView)
        splitView.setContent(
            left: AnyView(Color.clear),
            center: AnyView(Color.clear),
            right: AnyView(Color.clear)
        )
        splitView.configure(
            leftWidth: 250,
            centerWidth: 300,
            onResizeEnded: nil,
            appliesPosition: true
        )
        splitView.layoutSubtreeIfNeeded()
        let widthsBeforeDrag = splitView.arrangedSubviews.map(\.frame.width)

        ancestor.isTrackingDividerForDescendants = true
        splitView.setFrameSize(NSSize(width: 1_350, height: 700))
        splitView.configure(
            leftWidth: 360,
            centerWidth: 360,
            onResizeEnded: nil,
            appliesPosition: true
        )
        splitView.layoutSubtreeIfNeeded()

        #expect(splitView.arrangedSubviews[0].frame.width == widthsBeforeDrag[0])
        #expect(splitView.arrangedSubviews[1].frame.width == widthsBeforeDrag[1])
        #expect(
            abs(
                splitView.arrangedSubviews[2].frame.maxX
                    - splitView.bounds.maxX
            ) < 0.5
        )

        ancestor.isTrackingDividerForDescendants = false
        notifyDescendantSplitDividerTrackingEnded(in: ancestor)
        splitView.layoutSubtreeIfNeeded()

        #expect(abs(splitView.arrangedSubviews[0].frame.width - 360) < 0.5)
        #expect(abs(splitView.arrangedSubviews[1].frame.width - 360) < 0.5)
    }

    @Test("nested native split commits its pending position when ancestor drag ends")
    @MainActor
    func nativeSplitCommitsPendingAncestorDragPosition() {
        let ancestor = TestSplitTrackingAncestor(
            frame: NSRect(x: 0, y: 0, width: 1_100, height: 500)
        )
        let splitView = NativeSplitNSView(frame: ancestor.bounds)
        ancestor.addSubview(splitView)
        splitView.setContent(
            first: AnyView(Color.clear),
            second: AnyView(Color.clear)
        )
        splitView.configure(
            orientation: .horizontal,
            position: .points(250),
            minimumPosition: .points(180),
            maximumPosition: .points(600),
            minimumSecondLength: 360,
            onResize: nil,
            appliesPosition: true
        )
        splitView.layoutSubtreeIfNeeded()

        ancestor.isTrackingDividerForDescendants = true
        splitView.configure(
            orientation: .horizontal,
            position: .points(360),
            minimumPosition: .points(180),
            maximumPosition: .points(600),
            minimumSecondLength: 360,
            onResize: nil,
            appliesPosition: true
        )
        splitView.layoutSubtreeIfNeeded()
        #expect(abs(splitView.arrangedSubviews[0].frame.width - 250) < 0.5)

        ancestor.isTrackingDividerForDescendants = false
        notifyDescendantSplitDividerTrackingEnded(in: ancestor)

        #expect(abs(splitView.arrangedSubviews[0].frame.width - 360) < 0.5)
    }

    @Test("native split owns a cursor tracking area across the divider")
    @MainActor
    func nativeSplitOwnsDividerCursorTracking() {
        let splitView = NativeSplitNSView(
            frame: NSRect(x: 400, y: 0, width: 900, height: 400)
        )
        splitView.setContent(
            first: AnyView(Color.clear),
            second: AnyView(Color.clear)
        )
        splitView.configure(
            orientation: .horizontal,
            position: .points(280),
            minimumPosition: .points(180),
            maximumPosition: .points(440),
            minimumSecondLength: 360,
            onResize: nil,
            appliesPosition: true
        )
        splitView.layoutSubtreeIfNeeded()
        splitView.updateTrackingAreas()

        #expect(
            splitView.trackingAreas.contains {
                $0.options.contains(.cursorUpdate)
                    && $0.options.contains(.enabledDuringMouseDrag)
            }
        )
        #expect(splitView.hitTest(NSPoint(x: 680, y: 100)) === splitView)
        #expect(splitView.hitTest(NSPoint(x: 280, y: 100)) !== splitView)
        #expect(splitView.hitTest(NSPoint(x: 500, y: 100)) !== splitView)
    }

    @Test("fixed sidebar and terminal content extend beneath the title bar")
    func fixedColumnsUseTheFullWindowHeight() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let workbenchSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/BreathApp.swift"),
            encoding: .utf8
        )
        #expect(appSource.contains(".windowStyle(.hiddenTitleBar)"))
        #expect(workbenchSource.contains(".ignoresSafeArea(.container, edges: .top)"))
        #expect(workbenchSource.contains("NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)"))
        #expect(workbenchSource.contains("override var isFlipped: Bool { true }"))
        #expect(!workbenchSource.contains("isSidebarVisible"))
        #expect(!workbenchSource.contains("sidebar.left"))
    }

    @Test("sidebar resizing uses the native split view")
    func sidebarResizeUsesNativeSplitView() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )
        let resizeContainerStart = try #require(
            source.range(of: "private struct SidebarResizeContainer")
        )
        let nextViewStart = try #require(
            source.range(
                of: "private struct StateDot",
                range: resizeContainerStart.upperBound..<source.endIndex
            )
        )
        let resizeContainer = source[
            resizeContainerStart.lowerBound..<nextViewStart.lowerBound
        ]

        #expect(resizeContainer.contains("NativeSplitView"))
        #expect(!resizeContainer.contains("HSplitView"))
        #expect(!resizeContainer.contains("DragGesture"))
        #expect(!resizeContainer.contains("@State"))
    }

    @Test("terminal resizing uses the native split view")
    func terminalResizeUsesNativeSplitView() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )

        let splitContainerStart = try #require(
            source.range(of: "private struct SplitContainer")
        )
        let nextViewStart = try #require(
            source.range(
                of: "private struct TerminalPaneView",
                range: splitContainerStart.upperBound..<source.endIndex
            )
        )
        let splitContainer = source[
            splitContainerStart.lowerBound..<nextViewStart.lowerBound
        ]

        #expect(splitContainer.contains("NativeSplitView"))
        #expect(!splitContainer.contains("DragGesture"))
        #expect(!splitContainer.contains("@State"))
    }

    @Test("sidebar tree labels apply the application font directly")
    func sidebarTreeLabelsApplyApplicationFontDirectly() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("""
        Text(workspace.displayName)
                            .font(applicationFont(for: model))
        """))
        #expect(source.contains("""
        pane.agentBinding?.nativeTitle
                                            ?? localizer.format("终端 %d", index + 1)
                                    )
                                        .font(applicationFont(for: model))
        """))
        #expect(source.contains("""
        Text(session.title)
                                .font(applicationFont(for: model))
        """))
    }

    @Test("sidebar terminal rows request input focus")
    func sidebarTerminalRowsRequestInputFocus() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )
        let sessionTreeStart = try #require(
            source.range(of: "private func sessionTree")
        )
        let sessionRowStart = try #require(
            source.range(
                of: "private func sessionRow(",
                range: sessionTreeStart.upperBound..<source.endIndex
            )
        )
        let sessionTree = source[
            sessionTreeStart.lowerBound..<sessionRowStart.lowerBound
        ]

        #expect(
            sessionTree.contains(
                "requestTerminalFocus(session: session, pane: pane)"
            )
        )
    }

    @Test("sidebar footer omits Git while the terminal status opens the workbench")
    func terminalStatusOwnsTheGitEntry() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )
        let gitSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/BreathApp/GitWorkbenchView.swift"
            ),
            encoding: .utf8
        )
        let taskPanelStart = try #require(
            source.range(of: "if detailMode == .tasks")
        )
        let gitWorkbenchDetailStart = try #require(
            source.range(
                of: "} else if GitWorkbenchReleaseGate.isEnabled,",
                range: taskPanelStart.upperBound..<source.endIndex
            )
        )
        let taskPanel = source[
            taskPanelStart.lowerBound..<gitWorkbenchDetailStart.lowerBound
        ]
        let sidebarFooterStart = try #require(
            source.range(of: "private var sidebarFooter: some View")
        )
        let sidebarButtonFunctionStart = try #require(
            source.range(
                of: "private func sidebarFooterButton(",
                range: sidebarFooterStart.upperBound..<source.endIndex
            )
        )
        let sidebarFooter = source[
            sidebarFooterStart.lowerBound..<sidebarButtonFunctionStart.lowerBound
        ]
        let gitStatusStart = try #require(
            source.range(of: "private struct GitWorkingTreeStatusBar")
        )
        let gitIconStart = try #require(
            source.range(
                of: "private struct GitBranchIcon",
                range: gitStatusStart.upperBound..<source.endIndex
            )
        )
        let gitStatus = source[
            gitStatusStart.lowerBound..<gitIconStart.lowerBound
        ]
        let gitColumnsStart = try #require(
            gitSource.range(of: "private struct GitThreeColumnLayout")
        )
        let gitConsoleStart = try #require(
            gitSource.range(
                of: "private struct GitResizableConsole",
                range: gitColumnsStart.upperBound..<gitSource.endIndex
            )
        )
        let gitColumns = gitSource[
            gitColumnsStart.lowerBound..<gitConsoleStart.lowerBound
        ]
        let splitHostingStart = try #require(
            source.range(of: "final class NativeSplitHostingView")
        )
        let terminalPaneStart = try #require(
            source.range(
                of: "private struct TerminalPaneView",
                range: splitHostingStart.upperBound..<source.endIndex
            )
        )
        let splitHosting = source[
            splitHostingStart.lowerBound..<terminalPaneStart.lowerBound
        ]
        let nativeSplitStart = try #require(
            source.range(of: "final class NativeSplitNSView")
        )
        let nativeSplit = source[
            nativeSplitStart.lowerBound..<splitHostingStart.lowerBound
        ]

        #expect(source.contains("private var sidebarFooter: some View"))
        #expect(source.contains("@Environment(\\.openSettings) private var openSettings"))
        #expect(source.contains("openSettings()"))
        #expect(source.contains("detailMode = .tasks"))
        #expect(sidebarFooter.contains("WorkbenchAccessibility.openTaskView"))
        #expect(!sidebarFooter.contains("WorkbenchAccessibility.openGitWorkbench"))
        #expect(gitStatus.contains("Button(action: onOpenDiff)"))
        #expect(gitStatus.contains("GitBranchIcon()"))
        #expect(gitStatus.contains("WorkbenchAccessibility.openGitWorkbench"))
        #expect(gitSource.contains("preferencesStore.setDiffLayout(layout)"))
        #expect(gitSource.contains("GitShortcutEventHost("))
        #expect(!gitSource.contains("private var shortcutCommandHost: some View {\n        VStack"))
        #expect(gitSource.contains("private struct GitThreeColumnLayout"))
        #expect(gitSource.contains("private struct GitResizableConsole"))
        #expect(gitColumns.contains(": NSViewRepresentable"))
        #expect(gitColumns.contains("GitThreeColumnNSView"))
        #expect(!gitColumns.contains("NativeSplitView("))
        #expect(!gitColumns.contains("GeometryReader"))
        #expect(!gitColumns.contains("DragGesture"))
        #expect(!gitColumns.contains("@State"))
        #expect(source.contains("override func resetCursorRects()"))
        #expect(source.contains("enum DividerEdge"))
        #expect(source.contains("firstHostingView.configureDividerCursor("))
        #expect(source.contains("secondHostingView.configureDividerCursor("))
        #expect(splitHosting.contains("override func viewDidMoveToWindow()"))
        #expect(splitHosting.contains("window?.invalidateCursorRects(for: self)"))
        #expect(splitHosting.contains("addCursorRect(cursorRect, cursor: dividerCursor)"))
        #expect(nativeSplit.contains("override func updateTrackingAreas()"))
        #expect(nativeSplit.contains("override func cursorUpdate(with event: NSEvent)"))
        #expect(!nativeSplit.contains("override func hitTest("))
        #expect(nativeSplit.contains("super.mouseDown(with: event)"))
        #expect(!nativeSplit.contains("window.nextEvent("))
        #expect(!nativeSplit.contains("dragGuideLayer"))
        #expect(source.contains("isTrackingDivider"))
        #expect(source.contains("hasTrackingSplitAncestor"))
        #expect(source.contains("pendingContent"))
        #expect(source.contains("layer?.masksToBounds = true"))
        #expect(source.contains("if needsPositionUpdate(for: position)"))
        #expect(gitSource.contains("orientation: .vertical"))
        #expect(gitSource.contains(".frame(height: GitCommitGraphMetrics.rowHeight)"))
        #expect(gitSource.contains("private var selectedCommitInspector"))
        let commitInspectorStart = try #require(
            gitSource.range(of: "private var selectedCommitInspector")
        )
        let commitContextMenuStart = try #require(
            gitSource.range(
                of: "private func commitContextMenu(",
                range: commitInspectorStart.upperBound..<gitSource.endIndex
            )
        )
        let commitInspector = gitSource[
            commitInspectorStart.lowerBound..<commitContextMenuStart.lowerBound
        ]
        #expect(!commitInspector.contains("ScrollView(.horizontal)"))
        #expect(commitInspector.contains("LazyVStack"))
        #expect(commitInspector.contains("selectedDiffFileRequest = GitDiffFileRequest"))
        #expect(gitSource.contains("targetFileRequest: selectedDiffFileRequest"))
        #expect(gitSource.contains("proxy.scrollTo(fileID, anchor: .top)"))
        #expect(gitSource.contains("@StateObject private var documentStore"))
        #expect(gitSource.contains("GitPatchDocumentStore()"))
        #expect(!gitSource.contains("GitPatchDocumentStore(patch: diff.patch)"))
        #expect(gitSource.contains("Task.detached(priority: .userInitiated)"))
        #expect(gitSource.contains("await documentStore.load(patch: diff.patch)"))
        #expect(gitSource.contains("GitDelayedLoadingView"))
        #expect(gitSource.contains("ForEach(documentStore.unifiedRows)"))
        #expect(!gitSource.contains("_document = State(initialValue:"))
        #expect(gitSource.contains(".scrollContentBackground(.hidden)"))
        #expect(!gitSource.contains(".defaultScrollAnchor(.topLeading)"))
        #expect(gitSource.contains("private var unifiedDocument: some View"))
        #expect(gitSource.contains(".lineLimit(preferences.softWrap ? nil : 1)"))
        #expect(
            !gitSource.contains("maxWidth: preferences.softWrap ? .infinity : nil")
        )
        #expect(
            gitSource.contains(
                "guard model.metadata.localScrollAnchor != anchor else { return }"
            )
        )
        #expect(
            gitSource.contains(
                "guard model.metadata.logScrollAnchor != anchor else { return }"
            )
        )
        #expect(gitSource.contains("@State private var height: Double"))
        #expect(!gitSource.contains("value: $model.metadata.layout.leftWidth"))
        #expect(!gitSource.contains("model.metadata.layout.consoleHeight = min("))
        #expect(taskPanel.contains("Color(nsColor: .windowBackgroundColor)"))
        #expect(taskPanel.contains("WorkbenchAccessibility.taskViewPanel"))
        #expect(!taskPanel.contains("Text("))
    }

    @Test("settings omit the sidebar density control")
    func settingsOmitSidebarDensity() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let settingsSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/BreathApp/BreathSettingsView.swift"
            ),
            encoding: .utf8
        )
        let workbenchSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )

        #expect(!settingsSource.contains("侧边栏密度"))
        #expect(!settingsSource.contains("sidebarDensity"))
        #expect(!workbenchSource.contains("settings.application.sidebarDensity"))
    }

    @Test("workspace disclosure keeps balanced icon spacing")
    func workspaceDisclosureKeepsBalancedIconSpacing() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )

        #expect(
            source.contains(
                ".padding(.leading, WorkbenchLayout.sidebarWorkspaceDisclosureSpacing)"
            )
        )
        #expect(source.contains("sidebarWorkspaceDisclosureSpacing: CGFloat = 6"))
    }

    @Test("Git status is one workspace-wide bar below the terminal layout")
    func gitStatusIsWorkspaceWide() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )
        let workspaceLayoutStart = try #require(
            source.range(of: "private struct WorkSessionTerminalLayoutView")
        )
        let paneLayoutStart = try #require(
            source.range(
                of: "private struct PaneLayoutView",
                range: workspaceLayoutStart.upperBound..<source.endIndex
            )
        )
        let terminalPaneStart = try #require(
            source.range(of: "private struct TerminalPaneView")
        )
        let gitBarStart = try #require(
            source.range(
                of: "private struct GitWorkingTreeStatusBar",
                range: terminalPaneStart.upperBound..<source.endIndex
            )
        )
        let workspaceLayout = source[
            workspaceLayoutStart.lowerBound..<paneLayoutStart.lowerBound
        ]
        let terminalPane = source[
            terminalPaneStart.lowerBound..<gitBarStart.lowerBound
        ]

        #expect(workspaceLayout.contains("GitWorkingTreeStatusBar("))
        #expect(!terminalPane.contains("GitWorkingTreeStatusBar("))
    }

    @Test("sidebar and workspace status bars share one height")
    func bottomBarsShareOneHeight() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )
        let gitSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/GitWorkbenchView.swift"),
            encoding: .utf8
        )
        let consoleHeaderStart = try #require(
            gitSource.range(of: "private var consoleHeader: some View")
        )
        let consoleRecordsStart = try #require(
            gitSource.range(
                of: "private var consoleRecords: some View",
                range: consoleHeaderStart.upperBound..<gitSource.endIndex
            )
        )
        let consoleHeader = gitSource[
            consoleHeaderStart.lowerBound..<consoleRecordsStart.lowerBound
        ]
        let consoleLayoutStart = try #require(
            gitSource.range(of: "private struct GitResizableConsole")
        )
        let graphMetricsStart = try #require(
            gitSource.range(
                of: "private enum GitCommitGraphMetrics",
                range: consoleLayoutStart.upperBound..<gitSource.endIndex
            )
        )
        let consoleLayout = gitSource[
            consoleLayoutStart.lowerBound..<graphMetricsStart.lowerBound
        ]
        let sidebarStart = try #require(
            source.range(of: "private var sidebar: some View")
        )
        let sidebarFooterStart = try #require(
            source.range(
                of: "private var sidebarFooter: some View",
                range: sidebarStart.upperBound..<source.endIndex
            )
        )
        let sidebar = source[
            sidebarStart.lowerBound..<sidebarFooterStart.lowerBound
        ]
        let sidebarFooterButtonStart = try #require(
            source.range(
                of: "private func sidebarFooterButton(",
                range: sidebarFooterStart.upperBound..<source.endIndex
            )
        )
        let sidebarFooter = source[
            sidebarFooterStart.lowerBound..<sidebarFooterButtonStart.lowerBound
        ]

        #expect(source.contains("bottomBarHeight: CGFloat = 32"))
        #expect(!sidebar.contains("Divider()\n            sidebarFooter"))
        #expect(sidebarFooter.contains(".overlay(alignment: .top)"))
        #expect(consoleHeader.contains(".frame(height: WorkbenchLayout.bottomBarHeight)"))
        #expect(!consoleHeader.contains(".frame(height: 30)"))
        #expect(!consoleLayout.contains("Divider()\n            header"))
        #expect(consoleLayout.contains(".overlay(alignment: .top)"))
        #expect(!source.contains("sidebarFooterHeight"))
        #expect(!source.contains("terminalGitStatusBarHeight"))
        #expect(!source.contains("sidebarFooterHitArea"))
    }

    @Test("Git Console disclosure icon and label share one hit target")
    func gitConsoleDisclosureUsesCompleteHitTarget() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/GitWorkbenchView.swift"),
            encoding: .utf8
        )
        let headerStart = try #require(
            source.range(of: "private var consoleHeader: some View")
        )
        let recordsStart = try #require(
            source.range(
                of: "private var consoleRecords: some View",
                range: headerStart.upperBound..<source.endIndex
            )
        )
        let header = source[headerStart.lowerBound..<recordsStart.lowerBound]

        #expect(header.contains("Label("))
        #expect(header.contains(".contentShape(Rectangle())"))
    }

    @Test("passive Git diff empty state stays quiet and compact")
    func gitDiffEmptyStateIsCompact() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/GitWorkbenchView.swift"),
            encoding: .utf8
        )
        let detailsPaneStart = try #require(
            source.range(of: "private var detailsPane: some View")
        )
        let diffControlsStart = try #require(
            source.range(
                of: "private var diffControls: some View",
                range: detailsPaneStart.upperBound..<source.endIndex
            )
        )
        let detailsPane = source[
            detailsPaneStart.lowerBound..<diffControlsStart.lowerBound
        ]

        #expect(!detailsPane.contains("ContentUnavailableView("))
        #expect(detailsPane.contains("Text(localizer.string(\"选择一个变更或提交\"))"))
        #expect(detailsPane.contains(".font(.caption)"))
        #expect(detailsPane.contains(".foregroundStyle(.secondary)"))
    }

    @Test("Git dialogs stay compact and inherit the active application theme")
    func gitDialogsUseThemedSwiftUISurfaces() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let gitSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/GitWorkbenchView.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/BreathApp.swift"),
            encoding: .utf8
        )
        let terminalSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/BreathTerminal/GhosttyTerminalEngine.swift"
            ),
            encoding: .utf8
        )

        #expect(gitSource.contains("private struct GitCompactDialog: View"))
        #expect(gitSource.contains(".sheet(item: primaryDialogRequest)"))
        #expect(gitSource.contains(".font(.headline)"))
        #expect(gitSource.contains("static let textWidth: CGFloat = 380"))
        #expect(gitSource.contains(".frame(width: dialogWidth)"))
        #expect(!gitSource.contains("NSAlert()"))
        #expect(!gitSource.contains("promptForName("))
        #expect(gitSource.contains("applyDialogAppearance(to: panel)"))
        #expect(appSource.contains("alert.window.appearance ="))
        #expect(terminalSource.contains("alert.window.appearance = window?.effectiveAppearance"))
    }

    @Test("staging workflow exposes bulk stage and unstage actions")
    func stagingWorkflowHasBulkActions() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let viewSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/GitWorkbenchView.swift"),
            encoding: .utf8
        )
        let modelSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/GitWorkbenchViewModel.swift"),
            encoding: .utf8
        )

        #expect(viewSource.contains("actionTitle: localizer.string(\"全部暂存\")"))
        #expect(viewSource.contains("actionTitle: localizer.string(\"全部取消暂存\")"))
        #expect(viewSource.contains("action: model.stageAll"))
        #expect(viewSource.contains("action: model.unstageAll"))
        #expect(modelSource.contains("func stageAll()"))
        #expect(modelSource.contains("func unstageAll()"))
    }

    @Test("commit message editor protects active input method composition")
    func commitMessageEditorIsIMEAware() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/GitWorkbenchView.swift"),
            encoding: .utf8
        )
        let editorSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/BreathApp/GitCommitMessageEditor.swift"
            ),
            encoding: .utf8
        )
        let commitPanelStart = try #require(
            source.range(of: "private var commitPanel: some View")
        )
        let logPaneStart = try #require(
            source.range(
                of: "private var logPane: some View",
                range: commitPanelStart.upperBound..<source.endIndex
            )
        )
        let commitPanel = source[
            commitPanelStart.lowerBound..<logPaneStart.lowerBound
        ]

        #expect(commitPanel.contains("GitCommitMessageEditor("))
        #expect(!commitPanel.contains("TextEditor("))
        #expect(editorSource.contains("guard !textView.hasMarkedText() else { return }"))
    }

    @Test("Commit and Commit and Push share commit validation")
    func commitActionsShareDisabledState() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/GitWorkbenchView.swift"),
            encoding: .utf8
        )
        let commitPanelStart = try #require(
            source.range(of: "private var commitPanel: some View")
        )
        let logPaneStart = try #require(
            source.range(
                of: "private var logPane: some View",
                range: commitPanelStart.upperBound..<source.endIndex
            )
        )
        let commitPanel = source[
            commitPanelStart.lowerBound..<logPaneStart.lowerBound
        ]
        let sharedValidationUses = commitPanel.components(
            separatedBy: ".disabled(isCommitActionDisabled)"
        ).count - 1

        #expect(sharedValidationUses == 2)
        #expect(source.contains("private var isCommitActionDisabled: Bool"))
    }

    @Test("branch rows visibly highlight the selected reference")
    func branchRowsShowSelectionBackground() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/GitWorkbenchView.swift"),
            encoding: .utf8
        )
        let branchListStart = try #require(
            source.range(of: "private var branchList: some View")
        )
        let changesHeaderStart = try #require(
            source.range(
                of: "private var changesHeader: some View",
                range: branchListStart.upperBound..<source.endIndex
            )
        )
        let branchList = source[
            branchListStart.lowerBound..<changesHeaderStart.lowerBound
        ]

        #expect(source.contains("@State private var selectedBranchReferenceID: String?"))
        #expect(branchList.contains("selectedBranchReferenceID = reference.id"))
        #expect(branchList.contains("if isBranchSelected(reference)"))
        #expect(branchList.contains(".selectedContentBackgroundColor"))
    }

    @Test("Git toolbar keeps repository and remote actions task-scoped")
    func gitToolbarUsesTaskScopedControlHierarchy() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/GitWorkbenchView.swift"),
            encoding: .utf8
        )
        let toolbarStart = try #require(
            source.range(of: "private var toolbar: some View")
        )
        let contentStart = try #require(
            source.range(
                of: "private var content: some View",
                range: toolbarStart.upperBound..<source.endIndex
            )
        )
        let toolbar = source[toolbarStart.lowerBound..<contentStart.lowerBound]
        let rootPicker = try #require(toolbar.range(of: "rootPicker"))
        let refresh = try #require(toolbar.range(of: "\"arrow.clockwise\""))

        #expect(rootPicker.lowerBound < refresh.lowerBound)
        #expect(!toolbar.contains("branchMenu("))
        #expect(!toolbar.contains("allRepositoriesBranchMenu"))
        #expect(!toolbar.contains("TextField("))
        #expect(toolbar.contains("toolbarLabeledButton("))
        #expect(toolbar.contains("\"arrow.down.circle\",\n                \"Fetch\""))
        #expect(toolbar.contains("\"arrow.down.to.line\",\n                \"Pull\""))
        #expect(toolbar.contains("\"arrow.up.to.line\",\n                \"Push\""))
        #expect(toolbar.contains("toolbarIcon(\"wrench.and.screwdriver\")"))
        #expect(toolbar.contains("toolbarIcon(\"ellipsis.circle\")"))
        #expect(toolbar.contains("Spacer()\n                .frame(width: 4)"))
        #expect(source.contains("private func toolbarActionLabel("))
        #expect(source.contains("private func toolbarIcon("))
        #expect(source.contains("GitToolbarMetrics.iconPointSize"))
        #expect(source.contains("width: GitToolbarMetrics.iconFrameSize"))
        #expect(source.contains("height: GitToolbarMetrics.iconFrameSize"))

        let historyStart = try #require(
            source.range(of: "private func commitHistoryList")
        )
        let commitRowStart = try #require(
            source.range(
                of: "private func commitRow",
                range: historyStart.upperBound..<source.endIndex
            )
        )
        let history = source[historyStart.lowerBound..<commitRowStart.lowerBound]
        #expect(history.contains("TextField("))
        #expect(history.contains("localizer.string(\"搜索提交\")"))

        let settingsStart = try #require(
            source.range(of: "private struct GitWorkspaceSettingsView")
        )
        let stringExtensionStart = try #require(
            source.range(
                of: "private extension String",
                range: settingsStart.upperBound..<source.endIndex
            )
        )
        let settings = source[
            settingsStart.lowerBound..<stringExtensionStart.lowerBound
        ]
        #expect(settings.contains("@Environment(\\.dismiss)"))
        #expect(settings.contains("Button(localizer.string(\"完成\"))"))
        #expect(settings.contains("dismiss()"))

        let rootPickerStart = try #require(
            source.range(of: "private var rootPicker: some View")
        )
        let branchMenuStart = try #require(
            source.range(
                of: "private var allRepositoriesBranchMenu: some View",
                range: rootPickerStart.upperBound..<source.endIndex
            )
        )
        let rootPickerSource = source[
            rootPickerStart.lowerBound..<branchMenuStart.lowerBound
        ]
        #expect(rootPickerSource.contains(".fixedSize()"))
        #expect(!rootPickerSource.contains(".frame(maxWidth: 190)"))
    }

    @Test("workspace editor launcher is attached to the workspace status bar")
    func editorLauncherIsWorkspaceWide() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let workbenchSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )
        let launcherSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/BreathApp/WorkspaceEditorLauncher.swift"
            ),
            encoding: .utf8
        )

        #expect(workbenchSource.contains("WorkspaceEditorLauncher("))
        #expect(workbenchSource.contains("workspacePath: workspacePath"))
        #expect(launcherSource.contains("urlForApplication(withBundleIdentifier:"))
        #expect(launcherSource.contains("withApplicationAt: editor.applicationURL"))
    }
}
