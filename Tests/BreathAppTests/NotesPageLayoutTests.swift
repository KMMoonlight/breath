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

    @Test("the sidebar keeps creation actions but hides sort and undo controls")
    func sidebarKeepsOnlyTreeActions() throws {
        let notesSource = try compactSource("NotesView.swift")
        let sidebarHeader = try sourceSection(
            notesSource,
            from: "privatevarsidebarHeader",
            to: "privatevarfileBrowser"
        )
        let fileBrowser = try sourceSection(
            notesSource,
            from: "privatevarfileBrowser",
            to: "privatevarlibraryRootRow"
        )

        for icon in [
            "doc.badge.plus",
            "folder.badge.plus",
        ] {
            #expect(sidebarHeader.contains(icon))
            #expect(!fileBrowser.contains(icon))
        }
        #expect(!sidebarHeader.contains("arrow.up.arrow.down"))
        #expect(!sidebarHeader.contains("arrow.uturn.backward"))
        #expect(sidebarHeader.contains(".menuIndicator(.hidden)"))
        #expect(!notesSource.contains("privateenumNoteSortKey"))
    }

    @Test("the Notes split draws a boundary between the tree and editor")
    func notesSplitDrawsSidebarBoundary() throws {
        let notesSource = try compactSource("NotesView.swift")
        let notesLayout = try sourceSection(
            notesSource,
            from: "privatevarnotesLayout",
            to: "privatevarprimaryAlertContent"
        )

        #expect(notesLayout.contains("drawsDivider:true"))
    }

    @Test("the toolbar exposes library switching without paths or refresh")
    func toolbarUsesCompactLibraryMenu() throws {
        let notesSource = try compactSource("NotesView.swift")
        let toolbar = try sourceSection(
            notesSource,
            from: "privatevarnotesToolbar",
            to: "@ViewBuilderprivatevarshortcutButtons"
        )

        #expect(toolbar.contains("Text(library.displayName)"))
        #expect(toolbar.contains("Label(\"更换笔记库…\""))
        #expect(toolbar.contains("Image(systemName:\"sparkles\")"))
        #expect(!toolbar.contains("library.rootPath"))
        #expect(!toolbar.contains("Image(systemName:\"arrow.clockwise\")"))
        #expect(!toolbar.contains("Image(systemName:\"chevron.down\")"))
        #expect(!toolbar.contains("Image(systemName:\"magnifyingglass\")"))
        #expect(
            !toolbar.contains(
                "Image(systemName:\"square.and.arrow.down\")"
            )
        )
    }

    @Test("the Markdown outline expands from a rail beside the note text")
    func outlineExpandsFromTextRail() throws {
        let notesSource = try compactSource("NotesView.swift")
        let sidebarHeader = try sourceSection(
            notesSource,
            from: "privatevarsidebarHeader",
            to: "privatevarfileBrowser"
        )
        let editorArea = try sourceSection(
            notesSource,
            from: "privatevareditorArea",
            to: "privatefunceditor("
        )

        #expect(!sidebarHeader.contains("\"大纲\""))
        #expect(editorArea.contains("ifdocument.kind==.markdown"))
        #expect(editorArea.contains("ZStack(alignment:.topTrailing)"))
        #expect(
            editorArea.contains(
                "documentOutlineControl.padding(.top,NotesLayout.outlineTopInset)"
            )
        )
        #expect(editorArea.contains("outlineTrailingInset("))
        #expect(!editorArea.contains("Divider()documentOutline"))
        let outline = try sourceSection(
            notesSource,
            from: "privatevardocumentOutlineControl",
            to: "privatevarlibrarySearch"
        )
        #expect(!outline.contains("Text(\"大纲\")"))
        #expect(outline.contains("documentOutlineRail"))
        #expect(outline.contains(".onHover{hoveringin"))
        #expect(outline.contains("index==activeHeadingIndex"))
        #expect(outline.contains("NSCursor.pointingHand.push()"))
        #expect(outline.contains("Color(nsColor:.windowBackgroundColor)"))
        #expect(!outline.contains(".background(.regularMaterial"))
        #expect(outline.contains("ifoutlineContentHeight>NotesLayout.outlineMaximumHeight"))
        #expect(outline.contains("documentOutlineRows.fixedSize("))
        #expect(!outline.contains("height:min("))
    }

    @Test("the Note Agent header owns one combined launch selector")
    func noteAgentUsesOneHeaderLauncher() throws {
        let notesSource = try compactSource("NotesView.swift")
        let drawer = try sourceSection(
            notesSource,
            from: "privatestructNoteAgentDrawer",
            to: "privatestructNoteAgentNativeTerminalView"
        )
        let idleSelector = try sourceSection(
            String(drawer),
            from: "privatevaridleSelector",
            to: "@ViewBuilderprivatevaridleAgentLauncher"
        )
        let launcher = try sourceSection(
            String(drawer),
            from: "@ViewBuilderprivatevaridleAgentLauncher",
            to: "privatevarnoteAgentScopeHelp"
        )

        #expect(drawer.contains("Image(systemName:\"info.circle\")"))
        #expect(drawer.contains(".help(noteAgentScopeHelp)"))
        #expect(!idleSelector.contains("Picker("))
        #expect(!idleSelector.contains("Agent将以整座笔记库"))
        #expect(
            launcher.contains(
                "Text(\"启动\\(selectedAdapter.displayName)\")"
            )
        )
        #expect(launcher.contains(".menuIndicator(.hidden)"))
        #expect(launcher.contains("Image(systemName:\"chevron.down\")"))
    }

    @Test("document find and source controls live in the bottom utility bar")
    func editorControlsLiveAtTheBottom() throws {
        let notesSource = try compactSource("NotesView.swift")
        let editorArea = try sourceSection(
            notesSource,
            from: "privatevareditorArea",
            to: "privatefunceditorBottomBar"
        )
        let bottomBar = try sourceSection(
            notesSource,
            from: "privatefunceditorBottomBar",
            to: "privatefunceditor("
        )

        #expect(editorArea.contains("editorBottomBar(document)"))
        #expect(bottomBar.contains("Image(systemName:\"magnifyingglass\")"))
        #expect(
            bottomBar.contains(
                "\"chevron.left.forwardslash.chevron.right\""
            )
        )
        #expect(!bottomBar.contains("square.and.arrow.down"))
    }

    @Test("the file browser presents a disclosure tree rooted at the library")
    func fileBrowserUsesDisclosureTree() throws {
        let notesSource = try compactSource("NotesView.swift")
        let rootRow = try sourceSection(
            notesSource,
            from: "privatevarlibraryRootRow",
            to: "privatevardocumentOutline"
        )
        let entryRow = try sourceSection(
            notesSource,
            from: "privatestructNoteLibraryEntryRow",
            to: "privatestructNoteAgentDrawer"
        )

        #expect(rootRow.contains("\"chevron.down\""))
        #expect(rootRow.contains("\"chevron.right\""))
        #expect(rootRow.contains("selectedPaths.removeAll()"))
        #expect(rootRow.contains("ifselectedPaths.isEmpty"))
        #expect(rootRow.contains("Button(\"更换笔记库…\")"))
        #expect(entryRow.contains("ifentry.kind==.folder"))
        #expect(entryRow.contains("ForEach(0..<level"))
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
