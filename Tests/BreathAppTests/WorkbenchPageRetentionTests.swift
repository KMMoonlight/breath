import AppKit
import BreathTestSupport
import Foundation
import SwiftUI
import Testing
@testable import BreathApp

private enum RetainedPageFixture: Hashable {
    case workspace
    case git
}

@MainActor
private final class RetainedPageHarnessModel: ObservableObject {
    @Published var selection = RetainedPageSelection(
        initial: RetainedPageFixture.workspace
    )

    func select(_ page: RetainedPageFixture) {
        selection.select(page)
    }
}

@MainActor
private final class RetainedPageLifecycleRecorder {
    private(set) var appearances: [RetainedPageFixture: Int] = [:]
    private(set) var disappearances: [RetainedPageFixture: Int] = [:]

    func appeared(_ page: RetainedPageFixture) {
        appearances[page, default: 0] += 1
    }

    func disappeared(_ page: RetainedPageFixture) {
        disappearances[page, default: 0] += 1
    }
}

private struct RetainedPageHarness: View {
    @ObservedObject var model: RetainedPageHarnessModel
    let recorder: RetainedPageLifecycleRecorder

    var body: some View {
        RetainedPageDeck(selection: model.selection) { page in
            Color.clear
                .onAppear { recorder.appeared(page) }
                .onDisappear { recorder.disappeared(page) }
        }
    }
}

@Suite("Workbench page retention")
struct WorkbenchPageRetentionTests {
    @Test("selection retains each page once")
    func selectionRetainsEachPageOnce() {
        var selection = RetainedPageSelection(
            initial: RetainedPageFixture.workspace
        )

        selection.select(.git)
        selection.select(.workspace)
        selection.select(.git)

        #expect(selection.selected == .git)
        #expect(selection.retainedPages == [.workspace, .git])
    }

    @Test("switching visibility does not unmount a retained page")
    @MainActor
    func switchingVisibilityDoesNotUnmountRetainedPage() async {
        await NativeUITestGate.shared.acquire()
        defer { NativeUITestGate.shared.release() }
        _ = NSApplication.shared
        let model = RetainedPageHarnessModel()
        let recorder = RetainedPageLifecycleRecorder()
        let hostingView = NSHostingView(
            rootView: RetainedPageHarness(model: model, recorder: recorder)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        hostingView.layoutSubtreeIfNeeded()
        await settleViewUpdates()

        #expect(recorder.appearances[.workspace] == 1)
        #expect(recorder.disappearances[.workspace, default: 0] == 0)

        model.select(.git)
        await settleViewUpdates()
        model.select(.workspace)
        await settleViewUpdates()
        model.select(.git)
        await settleViewUpdates()

        #expect(recorder.appearances[.workspace] == 1)
        #expect(recorder.appearances[.git] == 1)
        #expect(recorder.disappearances[.workspace, default: 0] == 0)
        #expect(recorder.disappearances[.git, default: 0] == 0)
        NativeUITestLifetime.retainUntilProcessExit(hostingView)
    }

    @Test("activity bar keeps visited pages mounted")
    func activityBarKeepsVisitedPagesMounted() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/BreathApp/WorkbenchView.swift"
            ),
            encoding: .utf8
        )
        let contentStart = try #require(
            source.range(of: "private var workbenchContent: some View")
        )
        let activityBarStart = try #require(
            source.range(
                of: "private var activityBar: some View",
                range: contentStart.upperBound..<source.endIndex
            )
        )
        let content = source[
            contentStart.lowerBound..<activityBarStart.lowerBound
        ]

        #expect(
            source.contains(
                "@State private var pageSelection = RetainedPageSelection("
            )
        )
        #expect(content.contains("RetainedPageDeck(selection: pageSelection)"))
        #expect(content.contains("workbenchPage(for: page)"))
        #expect(!content.contains("if detailMode == .workspace"))
        #expect(
            source.contains(
                "private func selectDetailMode(_ mode: WorkbenchDetailMode)"
            )
        )
        #expect(source.contains("pageSelection.select(mode)"))
    }

    @MainActor
    private func settleViewUpdates() async {
        for _ in 0..<4 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}
