import AppKit
import BreathTestSupport
import Foundation
import SwiftUI
import Testing
@testable import BreathApp

private struct NotesSplitLayoutHarness: View {
    var body: some View {
        NativeSplitView(
            orientation: .horizontal,
            position: .points(250),
            minimumPosition: .points(180),
            maximumPosition: .points(420),
            minimumSecondLength: 420,
            updatesPosition: true
        ) {
            Color.clear
                .frame(minWidth: 180, maxWidth: 420)
        } second: {
            Color.clear
                .frame(minWidth: 420, maxWidth: .infinity)
        }
    }
}

private enum NotesPageLayoutTestError: Error {
    case missingSourceSection(String)
    case missingNativeSplit
}

@Suite("Notes page layout")
struct NotesPageLayoutTests {
    @Test("the Notes toolbar stays clear of the macOS window controls")
    func toolbarReservesWindowControlSpace() throws {
        let notesSource = try compactSource("NotesView.swift")
        let usesWindowAwareLeadingPadding = notesSource.contains(
            ".pageToolbarLeadingPadding()"
        )

        #expect(usesWindowAwareLeadingPadding)
    }

    @Test("an unconfigured Note Library uses the compact shared empty state")
    func unconfiguredLibraryUsesCompactSharedEmptyState() throws {
        let notesSource = try compactSource("NotesView.swift")
        let emptyState = try sourceSection(
            notesSource,
            from: "privatevarunconfiguredLibraryState",
            to: "privatevarunavailableLibraryState"
        )

        #expect(
            notesSource.contains(
                "ifmodel.snapshot.library==nil{unconfiguredLibraryState}"
            )
        )
        #expect(emptyState.contains("BreathEmptyState("))
        #expect(emptyState.contains("title:\"尚未选择笔记库\""))
        #expect(emptyState.contains("style:.passive"))
        #expect(emptyState.contains("Button(\"选择目录…\",action:chooseLibrary)"))
        #expect(!emptyState.contains("systemImage:"))
        #expect(!emptyState.contains("message:"))
    }

    @Test("the sidebar and Note Tab headers use one shared row height")
    func sidebarAndTabHeadersAlign() throws {
        let notesSource = try compactSource("NotesView.swift")
        let sidebarHeader = try sourceSection(
            notesSource,
            from: "privatevarsidebarHeader",
            to: "privatevarfileBrowser"
        )
        let noteTabBar = try sourceSection(
            notesSource,
            from: "privatevarnoteTabBar",
            to: "@ViewBuilderprivatefunctabContextMenu"
        )

        #expect(
            notesSource.contains(
                "staticletnavigationBarHeight:CGFloat=34"
            )
        )
        #expect(
            sidebarHeader.contains(
                ".frame(height:NotesLayout.navigationBarHeight)"
            )
        )
        #expect(
            noteTabBar.contains(
                ".frame(height:NotesLayout.navigationBarHeight)"
            )
        )
    }

    @Test("file creation actions live in the sidebar header, not its footer")
    func fileCreationActionsLiveAtTheTop() throws {
        let notesSource = try compactSource("NotesView.swift")
        let sidebarHeader = try sourceSection(
            notesSource,
            from: "privatevarsidebarHeader",
            to: "privatevarfileBrowser"
        )
        let fileBrowser = try sourceSection(
            notesSource,
            from: "privatevarfileBrowser",
            to: "privatevaroutline"
        )

        for icon in [
            "doc.badge.plus",
            "folder.badge.plus",
            "arrow.uturn.backward",
        ] {
            #expect(sidebarHeader.contains(icon))
            #expect(!fileBrowser.contains(icon))
        }
    }

    @Test("the Notes split keeps its resize hit target without drawing a line")
    func notesSplitDoesNotDrawAcrossTheEditorCanvas() throws {
        let notesSource = try compactSource("NotesView.swift")
        let notesLayout = try sourceSection(
            notesSource,
            from: "privatevarnotesLayout",
            to: "privatevarprimaryAlertContent"
        )

        #expect(notesLayout.contains("drawsDivider:false"))
    }

    @MainActor
    @Test("a wide Notes window keeps the sidebar at its configured width")
    func wideWindowKeepsConfiguredSidebarWidth() async throws {
        await NativeUITestGate.shared.acquire()
        defer { NativeUITestGate.shared.release() }
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_880, height: 1_000),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: NotesSplitLayoutHarness())
        window.contentView = hostingView

        for _ in 0..<4 {
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }

        guard let splitView = firstDescendant(
            of: NativeSplitNSView.self,
            in: hostingView
        ) else {
            throw NotesPageLayoutTestError.missingNativeSplit
        }
        let sidebarWidth = try #require(
            splitView.arrangedSubviews.first?.frame.width
        )
        #expect(abs(sidebarWidth - 250) < 1)
        NativeUITestLifetime.retainUntilProcessExit(hostingView)
        NativeUITestLifetime.retainUntilProcessExit(window)
    }

    private func compactSource(_ name: String) throws -> String {
        try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources/BreathApp")
                .appendingPathComponent(name),
            encoding: .utf8
        )
        .filter { !$0.isWhitespace }
    }

    private var packageRoot: URL {
        URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    }

    private func sourceSection(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        guard let start = source.range(of: startMarker) else {
            throw NotesPageLayoutTestError.missingSourceSection(startMarker)
        }
        guard let end = source.range(
            of: endMarker,
            range: start.upperBound..<source.endIndex
        ) else {
            throw NotesPageLayoutTestError.missingSourceSection(endMarker)
        }
        return source[start.lowerBound..<end.lowerBound]
    }

    @MainActor
    private func firstDescendant<ViewType: NSView>(
        of type: ViewType.Type,
        in root: NSView
    ) -> ViewType? {
        if let match = root as? ViewType {
            return match
        }
        for subview in root.subviews {
            if let match = firstDescendant(of: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
