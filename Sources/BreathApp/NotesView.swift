import AppKit
import BreathAgents
import BreathCore
import BreathNotes
import BreathTerminal
import SwiftUI

struct NotesView: View {
    @ObservedObject var applicationModel: BreathApplicationModel
    @ObservedObject var model: NotesApplicationModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.applicationLanguage) private var applicationLanguage
    @State private var sidebarMode: SidebarMode = .files
    @State private var filter = ""
    @State private var expandedPaths: Set<String> = []
    @State private var selectedPaths: Set<String> = []
    @State private var fileTreeHasFocus = false
    @State private var sortKey: NoteSortKey = .name
    @State private var sortAscending = true
    @State private var findQuery = ""
    @State private var findRevision = 0
    @State private var findBackwards = false
    @State private var showsDocumentFind = false
    @State private var pendingTabClose: PendingTabClose?
    @State private var pendingDelete: PendingFileDeletion?
    @State private var pendingImport: PendingFileImport?
    @State private var pendingMove: PendingFileMove?
    @State private var pendingRename: NoteLibraryEntry?
    @State private var renameValue = ""
    @State private var inlineRenamingPath: String?
    @State private var inlineRenameValue = ""
    @State private var conflictComparison: NoteDocument?
    @State private var pendingLibraryURL: URL?
    @State private var agentDrawerWidth: CGFloat = 420
    @State private var agentDrawerDragStart: CGFloat?

    init(applicationModel: BreathApplicationModel) {
        self.applicationModel = applicationModel
        model = applicationModel.notesModel
    }

    var body: some View {
        lifecycleAlertContent
            .background(shortcutButtons)
            .onAppear {
                agentDrawerWidth =
                    model.snapshot.preferences.agentDrawerWidth
                applicationModel.noteAgentModel.refreshAvailability()
                applicationModel.noteAgentModel.synchronizePersistence()
            }
            .onChange(of: model.inlineRenameRequest) { _, path in
                guard let path,
                      let entry = flatten(model.snapshot.entries).first(
                          where: { $0.relativePath == path }
                      )
                else {
                    return
                }
                inlineRenamingPath = path
                inlineRenameValue = entry.name
                selectedPaths = [path]
                expandParents(of: path)
                model.consumeInlineRenameRequest()
            }
    }

    private var notesLayout: some View {
        VStack(spacing: 0) {
            notesToolbar
            Divider()
            if model.snapshot.library == nil {
                unconfiguredLibraryState
            } else if !model.isLibraryAvailable {
                unavailableLibraryState
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        NativeSplitView(
                            orientation: .horizontal,
                            position: .points(
                                CGFloat(
                                    model.snapshot.preferences.sidebarWidth
                                )
                            ),
                            minimumPosition: .points(180),
                            maximumPosition: .points(420),
                            minimumSecondLength: 420,
                            drawsDivider: false,
                            updatesPosition: true,
                            onResize: { fraction in
                                let availableWidth = notesContentWidth(
                                    totalWidth: geometry.size.width
                                )
                                let width = min(
                                    max(
                                        availableWidth * CGFloat(fraction),
                                        180
                                    ),
                                    420
                                )
                                model.updatePreferences {
                                    $0.sidebarWidth = Double(width)
                                }
                            }
                        ) {
                            sidebar
                                .frame(minWidth: 180, maxWidth: 420)
                        } second: {
                            editorArea
                                .frame(minWidth: 420, maxWidth: .infinity)
                        }
                        if applicationModel.noteAgentModel.isDrawerPresented {
                            agentDrawerDivider(
                                maximumWidth: agentDrawerMaximumWidth(
                                    for: geometry.size.width
                                )
                            )
                            Divider()
                            NoteAgentDrawer(
                                model: applicationModel.noteAgentModel,
                                shortcutPolicy:
                                    applicationModel.settings.terminalShortcutPolicy
                            )
                            .frame(
                                width: constrainedAgentDrawerWidth(
                                    availableWidth: geometry.size.width
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    private var primaryAlertContent: some View {
        notesLayout
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(
            "笔记错误",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } }
            )
        ) {
            Button("好") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        .alert(
            pendingTabCloseTitle,
            isPresented: Binding(
                get: { pendingTabClose != nil },
                set: { if !$0 { pendingTabClose = nil } }
            )
        ) {
            Button("保存") {
                closePendingTabs(decision: .save)
            }
            Button("不保存", role: .destructive) {
                closePendingTabs(decision: .discard)
            }
            Button("取消", role: .cancel) {
                pendingTabClose = nil
            }
        } message: {
            Text("未保存的内容将不会写入 Markdown 文件。")
        }
        .alert(
            "移到废纸篓？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { deletion in
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("移到废纸篓", role: .destructive) {
                model.deleteItems(deletion.paths)
                selectedPaths.subtract(deletion.paths)
                pendingDelete = nil
            }
        } message: { deletion in
            Text("\(deletion.summary)将移到 macOS 废纸篓。未保存的标签内容会直接丢弃。")
        }
    }

    private var fileOperationAlertContent: some View {
        primaryAlertContent
        .alert(
            "重命名",
            isPresented: Binding(
                get: { pendingRename != nil },
                set: { if !$0 { pendingRename = nil } }
            ),
            presenting: pendingRename
        ) { entry in
            TextField("名称", text: $renameValue)
            Button("取消", role: .cancel) { pendingRename = nil }
            Button("重命名") {
                rename(entry, to: renameValue)
                pendingRename = nil
            }
        } message: { _ in
            Text("扩展名会保留为名称的一部分；相关的库内相对链接将一并更新。")
        }
        .alert(
            "同名项目已存在",
            isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            ),
            presenting: pendingImport
        ) { pending in
            Button("保留两者") {
                importPending(pending, resolution: .keepBoth)
            }
            Button("替换", role: .destructive) {
                importPending(pending, resolution: .replace)
            }
            Button("取消", role: .cancel) {
                pendingImport = nil
            }
        } message: { pending in
            Text(
                "\(pending.collidingNames.joined(separator: "、")) 已存在。此选择会应用到本次导入中的所有冲突。"
            )
        }
        .alert(
            "移动项目？",
            isPresented: Binding(
                get: { pendingMove != nil },
                set: { if !$0 { pendingMove = nil } }
            ),
            presenting: pendingMove
        ) { pending in
            Button("取消", role: .cancel) {
                pendingMove = nil
            }
            Button("移动") {
                model.moveItem(
                    from: pending.sourcePath,
                    to: pending.destinationPath
                )
                pendingMove = nil
            }
        } message: { pending in
            Text(
                "\(pending.sourcePath) 将移动到 \(pending.destinationPath)，并更新 \(pending.preview.affectedDocumentCount) 个文档中的 \(pending.preview.affectedLinkCount) 条相对链接。"
            )
        }
    }

    private var lifecycleAlertContent: some View {
        fileOperationAlertContent
        .alert(
            applicationModel.noteAgentModel.status == .idle
                ? "更换笔记库？"
                : "结束对话并更换笔记库？",
            isPresented: Binding(
                get: { pendingLibraryURL != nil },
                set: { if !$0 { pendingLibraryURL = nil } }
            )
        ) {
            Button("取消", role: .cancel) { pendingLibraryURL = nil }
            Button(
                model.hasDirtyDocuments
                    ? "丢弃修改并更换"
                    : "结束对话并更换",
                role: .destructive
            ) {
                if let url = pendingLibraryURL {
                    Task {
                        if applicationModel.noteAgentModel.status != .idle {
                            await applicationModel.noteAgentModel
                                .endConversation()
                        }
                        model.selectLibrary(
                            url,
                            discardUnsavedChanges: model.hasDirtyDocuments
                        )
                    }
                }
                pendingLibraryURL = nil
            }
        } message: {
            Text(librarySwitchMessage)
        }
        .sheet(item: $conflictComparison) { document in
            NoteConflictComparison(document: document)
        }
        .alert(
            "笔记 Agent 错误",
            isPresented: Binding(
                get: {
                    applicationModel.noteAgentModel.lastError != nil
                },
                set: {
                    if !$0 {
                        applicationModel.noteAgentModel.lastError = nil
                    }
                }
            )
        ) {
            Button("好") {
                applicationModel.noteAgentModel.lastError = nil
            }
        } message: {
            Text(applicationModel.noteAgentModel.lastError ?? "")
        }
    }

    private var notesToolbar: some View {
        HStack(spacing: 10) {
            Text(model.snapshot.library?.displayName ?? "笔记")
                .font(.headline)
                .lineLimit(1)
            if let library = model.snapshot.library {
                Text(library.rootPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            switch model.snapshot.searchIndexStatus {
            case .ready:
                EmptyView()
            case .rebuilding:
                ProgressView()
                    .controlSize(.small)
                    .help("正在重建全文索引")
            case .degraded:
                Label("全文索引需要重建", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("笔记文件仍可正常编辑和保存")
            }
            Spacer()
            if model.selectedDocument != nil {
                Button {
                    showsDocumentFind.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("在当前笔记中查找（⌘F）")

                Button {
                    model.toggleSourceMode()
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .help("切换 Markdown 源码（⌘/）")
                .keyboardShortcut("/", modifiers: .command)
                .disabled(model.selectedDocument?.kind == .plainText)

                Button {
                    model.saveSelectedDocument()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("保存（⌘S）")
                .keyboardShortcut("s", modifiers: .command)
            }
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新笔记库")

            Button {
                chooseLibrary()
            } label: {
                Image(systemName: "folder.badge.gearshape")
            }
            .help("更换笔记库")

            Button {
                applicationModel.noteAgentModel.isDrawerPresented.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                    if applicationModel.noteAgentModel.status != .idle {
                        Circle()
                            .fill(
                                applicationModel.noteAgentModel.status
                                    == .needsAttention
                                    ? Color.orange
                                    : Color.green
                            )
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .help(noteAgentButtonHelp)
            .disabled(!model.isLibraryAvailable)
            .accessibilityLabel(noteAgentButtonHelp)
        }
        .padding(.trailing, 12)
        .pageToolbarLeadingPadding()
        .frame(height: WorkbenchLayout.pageToolbarHeight)
    }

    @ViewBuilder
    private var shortcutButtons: some View {
        Group {
            Button("") {
                requestClose(ids: model.snapshot.selectedDocumentID.map { [$0] } ?? [])
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("") {
                model.createMarkdownDocument(in: selectedDirectoryPath)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("") {
                showsDocumentFind = true
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("") {
                sidebarMode = .search
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("") {
                model.undoLastFileOperation()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!fileTreeHasFocus)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var unconfiguredLibraryState: some View {
        BreathEmptyState(
            title: "尚未选择笔记库",
            style: .passive
        ) {
            Button("选择目录…", action: chooseLibrary)
        }
    }

    private var unavailableLibraryState: some View {
        BreathEmptyState(
            title: "笔记库不可访问",
            systemImage: "externaldrive.badge.exclamationmark",
            message: model.snapshot.library?.rootPath ?? ""
        ) {
            HStack {
                Button("重试") { model.refresh() }
                Button("在 Finder 中显示") {
                    guard let library = model.snapshot.library else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([
                        URL(fileURLWithPath: library.rootPath),
                    ])
                }
                Button("更换目录…", action: chooseLibrary)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            switch sidebarMode {
            case .files:
                fileBrowser
            case .outline:
                outline
            case .search:
                librarySearch
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sidebarHeader: some View {
        VStack(spacing: 0) {
            Picker("", selection: $sidebarMode) {
                Text("文件").tag(SidebarMode.files)
                Text("大纲").tag(SidebarMode.outline)
                Text("搜索").tag(SidebarMode.search)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .frame(height: NotesLayout.navigationBarHeight)

            Divider()

            if sidebarMode == .files {
                HStack(spacing: 6) {
                    TextField("筛选文件", text: $filter)
                        .textFieldStyle(.roundedBorder)
                    Menu {
                        Picker("排序", selection: $sortKey) {
                            Text("名称").tag(NoteSortKey.name)
                            Text("修改时间").tag(NoteSortKey.modified)
                            Text("创建时间").tag(NoteSortKey.created)
                        }
                        Divider()
                        Button(sortAscending ? "降序" : "升序") {
                            sortAscending.toggle()
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)

                    Menu {
                        Button {
                            model.createMarkdownDocument(
                                in: selectedDirectoryPath
                            )
                        } label: {
                            Label(
                                "新建 Markdown",
                                systemImage: "doc.badge.plus"
                            )
                        }
                        Button {
                            model.createFolder(in: selectedDirectoryPath)
                        } label: {
                            Label(
                                "新建文件夹",
                                systemImage: "folder.badge.plus"
                            )
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                    .help("新建笔记或文件夹")

                    Button {
                        model.undoLastFileOperation()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .help("撤销上一次文件操作")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)
                .frame(height: NotesLayout.navigationBarHeight)

                Divider()
            }
        }
    }

    private var fileBrowser: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredEntries) { entry in
                        NoteLibraryEntryRow(
                            entry: entry,
                            level: 0,
                            expandedPaths: $expandedPaths,
                            selectedPaths: $selectedPaths,
                            inlineRenamingPath: $inlineRenamingPath,
                            inlineRenameValue: $inlineRenameValue,
                            onOpen: model.open,
                            onCreateNote: {
                                model.createMarkdownDocument(
                                    in: directoryPath(for: $0)
                                )
                            },
                            onCreateFolder: {
                                model.createFolder(in: directoryPath(for: $0))
                            },
                            onRename: beginRename,
                            onCommitInlineRename: commitInlineRename,
                            onMove: requestMove,
                            onDelete: requestDelete,
                            onReveal: revealInFinder,
                            onCopy: copyFileReferences
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            .dropDestination(for: URL.self) { urls, _ in
                requestImport(urls)
                return !urls.isEmpty
            }
            .dropDestination(for: String.self) { paths, _ in
                for path in paths {
                    requestMove(path, "")
                }
                return !paths.isEmpty
            }
        }
        .onTapGesture {
            fileTreeHasFocus = true
        }
    }

    private var outline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(currentHeadings, id: \.offset) { heading in
                    Button {
                        findQuery = heading.title
                        findBackwards = false
                        findRevision += 1
                    } label: {
                        Text(heading.title)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(
                                .leading,
                                CGFloat(max(0, heading.level - 1)) * 12
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }

    private var librarySearch: some View {
        VStack(spacing: 0) {
            TextField(
                "搜索整座笔记库",
                text: Binding(
                    get: { model.searchQuery },
                    set: { model.searchLibrary($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .padding(8)

            if model.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .padding()
            } else if model.searchQuery.isEmpty {
                BreathEmptyState(
                    title: "全文搜索",
                    message: "搜索 Markdown、文本和 Front Matter；不提供替换。",
                    style: .passive
                )
            } else {
                List(model.searchResults) { result in
                    Button {
                        open(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.relativePath)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text("第 \(result.line) 行 · \(result.snippet)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var editorArea: some View {
        VStack(spacing: 0) {
            noteTabBar
            Divider()
            if showsDocumentFind, model.selectedDocument != nil {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("在当前笔记中查找", text: $findQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            requestNextFind(backwards: false)
                        }
                    Button {
                        requestNextFind(backwards: true)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(findQuery.isEmpty)
                    Button {
                        requestNextFind(backwards: false)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(findQuery.isEmpty)
                    Button {
                        showsDocumentFind = false
                        findQuery = ""
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                Divider()
            }
            if let document = model.selectedDocument {
                documentStateBanner(document)
                editor(document)
            } else if let imageURL = model.previewedImageURL,
                      let image = NSImage(contentsOf: imageURL)
            {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                }
            } else {
                BreathEmptyState(
                    title: "没有打开的笔记",
                    message: "从左侧文件树打开 Markdown 或文本文件。",
                    style: .passive
                )
            }
        }
        .onTapGesture {
            fileTreeHasFocus = false
        }
    }

    private func editor(_ document: NoteDocument) -> some View {
        VStack(spacing: 0) {
            if model.isSourceMode(document.id),
               document.kind == .markdown,
               NoteDocumentComplexity.analyze(document.content)
                .recommendedMode == .source
            {
                HStack {
                    Label(
                        "文档较大或结构复杂，已默认使用完整源码模式。",
                        systemImage: "gauge.with.dots.needle.67percent"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("尝试所见即所得") {
                        model.toggleSourceMode()
                    }
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                Divider()
            }
            NotesMarkdownEditor(
                document: document,
                libraryRoot: model.snapshot.library.map {
                    URL(fileURLWithPath: $0.rootPath, isDirectory: true)
                },
                sourceMode: model.isSourceMode(document.id),
                theme: currentTheme.rawValue,
                appearance: colorScheme == .dark ? "dark" : "light",
                language: ApplicationLocalizer(
                    language: applicationLanguage
                ).resolvedLanguage == .chinese ? "zh-Hans" : "en",
                showsCodeLineNumbers:
                    model.snapshot.preferences.showsCodeLineNumbers,
                spellCheckEnabled:
                    model.snapshot.preferences.spellCheckEnabled,
                findQuery: findQuery.isEmpty ? nil : findQuery,
                findRevision: findRevision,
                findBackwards: findBackwards,
                onChange: {
                    model.updateDocument(document.id, content: $0)
                },
                onOpenLink: openLink,
                onImportAttachment: { data, filename in
                    await model.importAttachment(
                        data: data,
                        filename: filename
                    )
                }
            )
            .id("shared-notes-editor")
        }
    }

    @ViewBuilder
    private func documentStateBanner(_ document: NoteDocument) -> some View {
        switch document.externalState {
        case .inSync:
            EmptyView()
        case .missing:
            HStack {
                Label("磁盘上的文件已不存在。内存内容仍保留，请另存为。", systemImage: "doc.badge.ellipsis")
                    .font(.caption)
                Spacer()
                Button("另存为…") { saveAs(document) }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.orange.opacity(0.14))
        case .conflict:
            HStack {
                Label("磁盘版本已被外部工具修改。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                Spacer()
                Button("比较") { conflictComparison = document }
                Button("用我的版本覆盖") {
                    model.resolveConflict(document.id, resolution: .overwriteDisk)
                }
                Button("重新加载磁盘版本") {
                    model.resolveConflict(document.id, resolution: .reloadDisk)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.orange.opacity(0.14))
        }
    }

    private var noteTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(model.snapshot.documents) { document in
                    HStack(spacing: 5) {
                        Button {
                            model.selectDocument(document.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text(tabTitle(document))
                                    .lineLimit(1)
                                if document.isDirty {
                                    Text("*")
                                        .accessibilityLabel("未保存")
                                }
                                if document.externalState != .inSync {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Button {
                            requestClose(ids: [document.id])
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭 \(tabTitle(document))")
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 34)
                    .background {
                        if document.id == model.snapshot.selectedDocumentID {
                            Color(nsColor: .textBackgroundColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .help(document.relativePath)
                    .draggable(document.id.rawValue.uuidString)
                    .dropDestination(for: String.self) { values, _ in
                        guard let raw = values.first,
                              let uuid = UUID(uuidString: raw),
                              let destination = model.snapshot.documents
                                .firstIndex(where: { $0.id == document.id })
                        else {
                            return false
                        }
                        model.moveDocumentTab(
                            NoteDocumentID(rawValue: uuid),
                            to: destination
                        )
                        return true
                    }
                    .contextMenu {
                        tabContextMenu(document)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityValue(document.isDirty ? "未保存" : "已保存")
                }
            }
        }
        .frame(height: NotesLayout.navigationBarHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func tabContextMenu(_ document: NoteDocument) -> some View {
        let ids = model.snapshot.documents.map(\.id)
        let index = ids.firstIndex(of: document.id) ?? 0
        Button("关闭") { requestClose(ids: [document.id]) }
        Button("关闭其他") {
            requestClose(ids: ids.filter { $0 != document.id })
        }
        Divider()
        Button("关闭左侧") {
            requestClose(ids: Array(ids.prefix(index)))
        }
        .disabled(index == 0)
        Button("关闭右侧") {
            requestClose(ids: Array(ids.dropFirst(index + 1)))
        }
        .disabled(index >= ids.count - 1)
        Button("全部关闭") { requestClose(ids: ids) }
    }

    private var filteredEntries: [NoteLibraryEntry] {
        let filtered = filter.isEmpty
            ? model.snapshot.entries
            : model.snapshot.entries.compactMap(filtered)
        return sorted(filtered)
    }

    private func filtered(_ entry: NoteLibraryEntry) -> NoteLibraryEntry? {
        let children = entry.children.compactMap(filtered)
        guard entry.name.localizedCaseInsensitiveContains(filter)
            || !children.isEmpty
        else {
            return nil
        }
        return NoteLibraryEntry(
            relativePath: entry.relativePath,
            name: entry.name,
            kind: entry.kind,
            children: children,
            creationDate: entry.creationDate,
            modificationDate: entry.modificationDate
        )
    }

    private func sorted(_ entries: [NoteLibraryEntry]) -> [NoteLibraryEntry] {
        entries.map {
            NoteLibraryEntry(
                relativePath: $0.relativePath,
                name: $0.name,
                kind: $0.kind,
                children: sorted($0.children),
                creationDate: $0.creationDate,
                modificationDate: $0.modificationDate
            )
        }.sorted { lhs, rhs in
            if (lhs.kind == .folder) != (rhs.kind == .folder) {
                return lhs.kind == .folder
            }
            let result: ComparisonResult
            switch sortKey {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name)
            case .modified:
                result = compare(lhs.modificationDate, rhs.modificationDate)
            case .created:
                result = compare(lhs.creationDate, rhs.creationDate)
            }
            return sortAscending
                ? result == .orderedAscending
                : result == .orderedDescending
        }
    }

    private func compare(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): lhs.compare(rhs)
        case (nil, nil): .orderedSame
        case (nil, _): .orderedAscending
        case (_, nil): .orderedDescending
        }
    }

    private var currentHeadings:
        [(offset: Int, level: Int, title: String)]
    {
        guard let content = model.selectedDocument?.content else { return [] }
        return content.split(separator: "\n").enumerated().compactMap {
            offset,
            line in
            let prefix = line.prefix { $0 == "#" }
            guard !prefix.isEmpty, prefix.count <= 6,
                  line.dropFirst(prefix.count).first == " "
            else {
                return nil
            }
            return (
                offset,
                prefix.count,
                String(line.dropFirst(prefix.count + 1))
            )
        }
    }

    private var currentTheme: NoteMarkdownTheme {
        colorScheme == .dark
            ? model.snapshot.preferences.darkTheme
            : model.snapshot.preferences.lightTheme
    }

    private var noteAgentButtonHelp: String {
        switch applicationModel.noteAgentModel.status {
        case .idle:
            "打开笔记 Agent"
        case .running:
            "笔记 Agent 正在运行"
        case .needsAttention:
            "笔记 Agent 需要处理"
        }
    }

    private func agentDrawerMaximumWidth(for availableWidth: CGFloat) -> CGFloat {
        max(340, min(720, availableWidth * 0.45))
    }

    private func constrainedAgentDrawerWidth(
        availableWidth: CGFloat
    ) -> CGFloat {
        min(
            max(agentDrawerWidth, 340),
            agentDrawerMaximumWidth(for: availableWidth)
        )
    }

    private func notesContentWidth(totalWidth: CGFloat) -> CGFloat {
        guard applicationModel.noteAgentModel.isDrawerPresented else {
            return totalWidth
        }
        return max(
            0,
            totalWidth
                - constrainedAgentDrawerWidth(availableWidth: totalWidth)
                - 6
        )
    }

    private func agentDrawerDivider(
        maximumWidth: CGFloat
    ) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let start = agentDrawerDragStart ?? agentDrawerWidth
                        agentDrawerDragStart = start
                        agentDrawerWidth = min(
                            max(start - value.translation.width, 340),
                            maximumWidth
                        )
                    }
                    .onEnded { _ in
                        agentDrawerDragStart = nil
                        let width = Double(agentDrawerWidth)
                        model.updatePreferences {
                            $0.agentDrawerWidth = width
                        }
                    }
            )
    }

    private var selectedDirectoryPath: String {
        guard selectedPaths.count == 1,
              let path = selectedPaths.first,
              let entry = flatten(model.snapshot.entries).first(where: {
                  $0.relativePath == path
              })
        else {
            return ""
        }
        if entry.kind == .folder {
            return entry.relativePath
        }
        let parent = (entry.relativePath as NSString)
            .deletingLastPathComponent
        return parent == "." ? "" : parent
    }

    private var pendingTabCloseTitle: String {
        guard let pendingTabClose else { return "关闭标签？" }
        return pendingTabClose.ids.count > 1
            ? "关闭 \(pendingTabClose.ids.count) 个标签？"
            : "保存对此笔记的修改？"
    }

    private func requestClose(ids: [NoteDocumentID]) {
        guard !ids.isEmpty else { return }
        let dirty = Set(
            model.snapshot.documents.filter(\.isDirty).map(\.id)
        )
        if ids.contains(where: dirty.contains) {
            pendingTabClose = PendingTabClose(ids: ids)
        } else {
            model.closeDocuments(ids, decision: .discard)
        }
    }

    private func closePendingTabs(decision: NoteCloseDecision) {
        guard let ids = pendingTabClose?.ids else { return }
        model.closeDocuments(ids, decision: decision)
        pendingTabClose = nil
    }

    private func tabTitle(_ document: NoteDocument) -> String {
        NoteTabTitle.disambiguated(
            relativePath: document.relativePath,
            among: model.snapshot.documents.map(\.relativePath)
        )
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择笔记库"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if model.hasDirtyDocuments
            || applicationModel.noteAgentModel.status != .idle
        {
            pendingLibraryURL = url
        } else {
            model.selectLibrary(url)
        }
    }

    private var librarySwitchMessage: String {
        switch (
            model.hasDirtyDocuments,
            applicationModel.noteAgentModel.status != .idle
        ) {
        case (true, true):
            "当前有未保存的笔记和运行中的笔记 Agent。继续会丢弃内存修改并结束对话，但不会移动或删除旧笔记库。"
        case (true, false):
            "当前有未保存的笔记。继续会丢弃这些内存修改，但不会移动或删除旧笔记库。"
        case (false, true):
            "笔记 Agent 仍在旧笔记库中运行。继续会显式结束该对话，再切换笔记库。"
        case (false, false):
            "将切换全局笔记库。"
        }
    }

    private func requestImport(_ urls: [URL]) {
        guard !urls.isEmpty, let library = model.snapshot.library else {
            return
        }
        let directory = URL(
            fileURLWithPath: library.rootPath,
            isDirectory: true
        ).appendingPathComponent(selectedDirectoryPath, isDirectory: true)
        let collisions = urls.compactMap { source -> String? in
            let name = source.lastPathComponent
            return FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(name).path
            ) ? name : nil
        }
        guard !collisions.isEmpty else {
            model.importItems(
                urls,
                into: selectedDirectoryPath,
                conflictResolution: .keepBoth
            )
            return
        }
        pendingImport = PendingFileImport(
            urls: urls,
            directory: selectedDirectoryPath,
            collidingNames: collisions
        )
    }

    private func importPending(
        _ pending: PendingFileImport,
        resolution: NoteImportConflictResolution
    ) {
        model.importItems(
            pending.urls,
            into: pending.directory,
            conflictResolution: resolution
        )
        pendingImport = nil
    }

    private func requestMove(
        _ sourcePath: String,
        _ destinationDirectory: String
    ) {
        let name = (sourcePath as NSString).lastPathComponent
        let destinationPath = destinationDirectory.isEmpty
            ? name
            : "\(destinationDirectory)/\(name)"
        guard sourcePath != destinationPath else { return }
        Task {
            do {
                let preview = try await model.previewMove(
                    from: sourcePath,
                    to: destinationPath
                )
                pendingMove = PendingFileMove(
                    sourcePath: sourcePath,
                    destinationPath: destinationPath,
                    preview: preview
                )
            } catch {
                model.lastError = error.localizedDescription
            }
        }
    }

    private func beginRename(_ entry: NoteLibraryEntry) {
        renameValue = entry.name
        pendingRename = entry
    }

    private func commitInlineRename(_ entry: NoteLibraryEntry) {
        let value = inlineRenameValue
        inlineRenamingPath = nil
        guard value != entry.name else { return }
        rename(entry, to: value)
    }

    private func expandParents(of relativePath: String) {
        var components = relativePath.split(separator: "/").map(String.init)
        guard components.count > 1 else { return }
        components.removeLast()
        var path = ""
        for component in components {
            path = path.isEmpty ? component : "\(path)/\(component)"
            expandedPaths.insert(path)
        }
    }

    private func rename(_ entry: NoteLibraryEntry, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            model.lastError = "名称不能为空，也不能包含斜杠。"
            return
        }
        let parent = NSString(
            string: entry.relativePath
        ).deletingLastPathComponent
        let destination = parent.isEmpty
            ? trimmed
            : "\(parent)/\(trimmed)"
        model.moveItem(from: entry.relativePath, to: destination)
    }

    private func directoryPath(for entry: NoteLibraryEntry) -> String {
        if entry.kind == .folder {
            return entry.relativePath
        }
        return NSString(
            string: entry.relativePath
        ).deletingLastPathComponent
    }

    private func requestDelete(_ entry: NoteLibraryEntry) {
        let paths = selectedPaths.contains(entry.relativePath)
            ? Array(selectedPaths)
            : [entry.relativePath]
        pendingDelete = PendingFileDeletion(
            paths: paths,
            summary: paths.count == 1
                ? "“\(entry.name)”"
                : "所选 \(paths.count) 个项目"
        )
    }

    private func revealInFinder(_ entry: NoteLibraryEntry) {
        guard let root = model.snapshot.library?.rootPath else { return }
        let paths = selectedPaths.contains(entry.relativePath)
            ? Array(selectedPaths)
            : [entry.relativePath]
        NSWorkspace.shared.activateFileViewerSelecting(paths.map {
            URL(fileURLWithPath: root).appendingPathComponent($0)
        })
    }

    private func copyFileReferences(_ entry: NoteLibraryEntry) {
        guard let root = model.snapshot.library?.rootPath else { return }
        let paths = selectedPaths.contains(entry.relativePath)
            ? Array(selectedPaths)
            : [entry.relativePath]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(paths.map {
            URL(fileURLWithPath: root)
                .appendingPathComponent($0) as NSURL
        })
    }

    private func open(_ result: NoteSearchResult) {
        guard let entry = flatten(model.snapshot.entries).first(where: {
            $0.relativePath == result.relativePath
        }) else { return }
        model.open(entry)
        findQuery = model.searchQuery
        findBackwards = false
        findRevision += 1
        showsDocumentFind = true
    }

    private func requestNextFind(backwards: Bool) {
        guard !findQuery.isEmpty else { return }
        findBackwards = backwards
        findRevision += 1
    }

    private func openLink(_ href: String) {
        guard let library = model.snapshot.library,
              let document = model.selectedDocument
        else { return }
        if let url = URL(string: href), let scheme = url.scheme {
            if ["https", "http", "mailto"].contains(scheme.lowercased()) {
                NSWorkspace.shared.open(url)
            } else if scheme.lowercased() == "file" {
                openLocalTarget(
                    url.standardizedFileURL,
                    root: URL(
                        fileURLWithPath: library.rootPath,
                        isDirectory: true
                    ).standardizedFileURL,
                    document: document,
                    fragment: url.fragment
                )
            } else {
                model.lastError = "不支持此链接"
            }
            return
        }
        let path = href.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? href
        let root = URL(fileURLWithPath: library.rootPath, isDirectory: true)
            .standardizedFileURL
        let base = root.appendingPathComponent(document.relativePath)
            .deletingLastPathComponent()
        let target = base.appendingPathComponent(
            path.removingPercentEncoding ?? path
        ).standardizedFileURL
        let fragment = href.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).dropFirst().first.map(String.init)
        openLocalTarget(
            target,
            root: root,
            document: document,
            fragment: fragment
        )
    }

    private func openLocalTarget(
        _ target: URL,
        root: URL,
        document: NoteDocument,
        fragment: String?
    ) {
        guard FileManager.default.fileExists(atPath: target.path) else {
            model.lastError = "目标不存在"
            return
        }
        let boundary = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if target.path.hasPrefix(boundary) {
            let documentDirectory = root.appendingPathComponent(
                document.relativePath
            ).deletingLastPathComponent()
            let relativeFromDocument = relativePath(
                from: documentDirectory,
                to: target
            )
            do {
                _ = try NoteResourceResolver.resolveExistingLocalResource(
                    relativeFromDocument,
                    relativeTo: document.relativePath,
                    libraryRoot: root
                )
            } catch {
                model.lastError = error.localizedDescription
                return
            }
        }
        if target.path.hasPrefix(boundary),
           ["md", "markdown", "txt"].contains(
            target.pathExtension.lowercased()
           ) {
            let relative = String(target.path.dropFirst(boundary.count))
            if let entry = flatten(model.snapshot.entries).first(where: {
                $0.relativePath == relative
            }) {
                model.open(entry)
                if let fragment, !fragment.isEmpty {
                    findQuery = (
                        fragment.removingPercentEncoding ?? fragment
                    ).replacingOccurrences(of: "-", with: " ")
                    findBackwards = false
                    findRevision += 1
                    showsDocumentFind = true
                }
            }
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    private func relativePath(from directory: URL, to target: URL) -> String {
        let baseComponents = directory.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        var common = 0
        while common < baseComponents.count,
              common < targetComponents.count,
              baseComponents[common] == targetComponents[common]
        {
            common += 1
        }
        return Array(
            repeating: "..",
            count: baseComponents.count - common
        ).joined(separator: "/")
            + (baseComponents.count == common ? "" : "/")
            + targetComponents.dropFirst(common).joined(separator: "/")
    }

    private func saveAs(_ document: NoteDocument) {
        guard let library = model.snapshot.library else { return }
        let panel = NSSavePanel()
        panel.directoryURL = URL(
            fileURLWithPath: library.rootPath,
            isDirectory: true
        )
        panel.nameFieldStringValue = URL(
            fileURLWithPath: document.relativePath
        ).lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let root = URL(fileURLWithPath: library.rootPath).standardizedFileURL
        let target = url.standardizedFileURL
        let boundary = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard target.path.hasPrefix(boundary) else {
            model.lastError = "只能另存到当前笔记库中"
            return
        }
        let relative = String(target.path.dropFirst(boundary.count))
        Task {
            do {
                _ = try await model.saveDocument(document.id, as: relative)
            } catch {
                model.lastError = error.localizedDescription
            }
        }
    }

    private func flatten(
        _ entries: [NoteLibraryEntry]
    ) -> [NoteLibraryEntry] {
        entries.flatMap { [$0] + flatten($0.children) }
    }
}

private enum NotesLayout {
    static let navigationBarHeight: CGFloat = 34
}

private enum SidebarMode {
    case files
    case outline
    case search
}

private enum NoteSortKey {
    case name
    case modified
    case created
}

private struct PendingTabClose {
    let ids: [NoteDocumentID]
}

private struct PendingFileDeletion {
    let paths: [String]
    let summary: String
}

private struct PendingFileImport {
    let urls: [URL]
    let directory: String
    let collidingNames: [String]
}

private struct PendingFileMove {
    let sourcePath: String
    let destinationPath: String
    let preview: NoteMovePreview
}

private struct NoteLibraryEntryRow: View {
    let entry: NoteLibraryEntry
    let level: Int
    @Binding var expandedPaths: Set<String>
    @Binding var selectedPaths: Set<String>
    @Binding var inlineRenamingPath: String?
    @Binding var inlineRenameValue: String
    let onOpen: (NoteLibraryEntry) -> Void
    let onCreateNote: (NoteLibraryEntry) -> Void
    let onCreateFolder: (NoteLibraryEntry) -> Void
    let onRename: (NoteLibraryEntry) -> Void
    let onCommitInlineRename: (NoteLibraryEntry) -> Void
    let onMove: (String, String) -> Void
    let onDelete: (NoteLibraryEntry) -> Void
    let onReveal: (NoteLibraryEntry) -> Void
    let onCopy: (NoteLibraryEntry) -> Void
    @FocusState private var isInlineRenameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                let isExtendingSelection =
                    NSApp.currentEvent?.modifierFlags.contains(.command)
                        == true
                if isExtendingSelection {
                    if selectedPaths.contains(entry.relativePath) {
                        selectedPaths.remove(entry.relativePath)
                    } else {
                        selectedPaths.insert(entry.relativePath)
                    }
                } else {
                    selectedPaths = [entry.relativePath]
                }
                if entry.kind == .folder {
                    if expandedPaths.contains(entry.relativePath) {
                        expandedPaths.remove(entry.relativePath)
                    } else {
                        expandedPaths.insert(entry.relativePath)
                    }
                } else {
                    onOpen(entry)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: iconName)
                        .frame(width: 14)
                    if inlineRenamingPath == entry.relativePath {
                        TextField("", text: $inlineRenameValue)
                            .textFieldStyle(.plain)
                            .focused($isInlineRenameFocused)
                            .onSubmit {
                                onCommitInlineRename(entry)
                            }
                            .onExitCommand {
                                inlineRenamingPath = nil
                            }
                            .onAppear {
                                DispatchQueue.main.async {
                                    isInlineRenameFocused = true
                                }
                            }
                    } else {
                        Text(entry.name)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, CGFloat(level) * 14)
                .padding(.horizontal, 4)
                .frame(height: 24)
                .contentShape(Rectangle())
                .background {
                    if selectedPaths.contains(entry.relativePath) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.18))
                    }
                }
            }
            .buttonStyle(.plain)
            .draggable(entry.relativePath)
            .dropDestination(for: String.self) { paths, _ in
                guard entry.kind == .folder else { return false }
                for path in paths {
                    onMove(path, entry.relativePath)
                }
                return !paths.isEmpty
            }
            .contextMenu {
                if entry.kind == .folder {
                    Button("新建 Markdown") { onCreateNote(entry) }
                    Button("新建文件夹") { onCreateFolder(entry) }
                    Divider()
                }
                Button("重命名…") { onRename(entry) }
                    .disabled(
                        selectedPaths.contains(entry.relativePath)
                            && selectedPaths.count > 1
                    )
                Button("复制") { onCopy(entry) }
                Button("在 Finder 中显示") { onReveal(entry) }
                Divider()
                Button("移到废纸篓", role: .destructive) {
                    onDelete(entry)
                }
            }

            if entry.kind == .folder,
               expandedPaths.contains(entry.relativePath)
            {
                ForEach(entry.children) { child in
                    NoteLibraryEntryRow(
                        entry: child,
                        level: level + 1,
                        expandedPaths: $expandedPaths,
                        selectedPaths: $selectedPaths,
                        inlineRenamingPath: $inlineRenamingPath,
                        inlineRenameValue: $inlineRenameValue,
                        onOpen: onOpen,
                        onCreateNote: onCreateNote,
                        onCreateFolder: onCreateFolder,
                        onRename: onRename,
                        onCommitInlineRename: onCommitInlineRename,
                        onMove: onMove,
                        onDelete: onDelete,
                        onReveal: onReveal,
                        onCopy: onCopy
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var iconName: String {
        switch entry.kind {
        case .folder:
            expandedPaths.contains(entry.relativePath)
                ? "folder.fill"
                : "folder"
        case .markdown:
            "doc.richtext"
        case .plainText:
            "doc.plaintext"
        case .image:
            "photo"
        case .pdf:
            "doc.fill"
        case .attachment:
            "paperclip"
        }
    }
}

private struct NoteAgentDrawer: View {
    @ObservedObject var model: NoteAgentApplicationModel
    let shortcutPolicy: TerminalShortcutPolicy
    @State private var selectedKind: AgentKind?
    @State private var showsEndConfirmation = false
    @State private var pendingSwitch: AgentAdapterDescriptor?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("笔记 Agent", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                if model.status != .idle {
                    Label(
                        model.status == .needsAttention ? "需要处理" : "运行中",
                        systemImage: model.status == .needsAttention
                            ? "exclamationmark.circle.fill"
                            : "circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        model.status == .needsAttention ? .orange : .green
                    )
                }
            }
            .padding(.horizontal, 12)
            .frame(height: WorkbenchLayout.pageToolbarHeight)
            Divider()

            if let terminalID = model.terminalID {
                runningTerminal(terminalID)
            } else {
                idleSelector
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.refreshAvailability()
            selectedKind = model.selectedAgent
                ?? model.availableAgents.first?.kind
        }
        .onChange(of: model.selectedAgent) { _, value in
            if let value { selectedKind = value }
        }
        .alert("结束当前对话？", isPresented: $showsEndConfirmation) {
            Button("取消", role: .cancel) {}
            Button("结束对话", role: .destructive) {
                Task { await model.endConversation() }
            }
        } message: {
            Text("终端进程会停止，Breath 的继续绑定会清除；Agent CLI 自己保存的历史不会被删除。")
        }
        .alert(
            "切换 Agent？",
            isPresented: Binding(
                get: { pendingSwitch != nil },
                set: { if !$0 { pendingSwitch = nil } }
            ),
            presenting: pendingSwitch
        ) { adapter in
            Button("取消", role: .cancel) { pendingSwitch = nil }
            Button("结束并切换", role: .destructive) {
                Task {
                    await model.endConversation()
                    await launch(adapter, resumeSessionID: nil)
                    pendingSwitch = nil
                }
            }
        } message: { adapter in
            Text("当前终端会先结束，然后启动 \(adapter.displayName)。")
        }
    }

    private var idleSelector: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.availableAgents.isEmpty {
                BreathEmptyState(
                    title: "没有可用的 Agent CLI",
                    systemImage: "terminal",
                    message: "安装 Breath 支持的 Agent CLI 后重新打开此抽屉。"
                )
            } else {
                Text("Agent 将以整座笔记库为工作目录运行。Breath 不会注入当前笔记内容，也不会额外限制 CLI 权限。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Agent", selection: $selectedKind) {
                    ForEach(model.availableAgents, id: \.kind) { adapter in
                        Text(adapter.displayName)
                            .tag(Optional(adapter.kind))
                    }
                }

                if let recovery = model.recoveryBinding,
                   let adapter = model.availableAgents.first(where: {
                       $0.kind == recovery.agent
                   })
                {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("上次对话")
                            .font(.caption.weight(.semibold))
                        Button("继续 \(adapter.displayName) 对话") {
                            Task {
                                await launch(
                                    adapter,
                                    resumeSessionID: recovery.sessionID
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("开始新对话") {
                            Task {
                                await launch(
                                    selectedAdapter ?? adapter,
                                    resumeSessionID: nil
                                )
                            }
                        }
                    }
                } else if let selectedAdapter {
                    HStack(spacing: 0) {
                        Button("启动 \(selectedAdapter.displayName)") {
                            Task {
                                await launch(
                                    selectedAdapter,
                                    resumeSessionID: nil
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        Menu {
                            ForEach(model.availableAgents, id: \.kind) {
                                adapter in
                                Button(adapter.displayName) {
                                    selectedKind = adapter.kind
                                    Task {
                                        await launch(
                                            adapter,
                                            resumeSessionID: nil
                                        )
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 28)
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func runningTerminal(
        _ terminalID: NoteAgentTerminalID
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(selectedAdapter?.displayName ?? "Agent CLI")
                    .font(.callout.weight(.medium))
                Spacer()
                Menu {
                    ForEach(model.availableAgents, id: \.kind) { adapter in
                        Button("切换到 \(adapter.displayName)") {
                            pendingSwitch = adapter
                        }
                        .disabled(adapter.kind == model.selectedAgent)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26)
                .help("切换 Agent")

                Button("结束对话") {
                    showsEndConfirmation = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            Divider()
            NoteAgentNativeTerminalView(
                engine: model.terminalEngine,
                terminalID: terminalID,
                shortcutPolicy: shortcutPolicy
            )
        }
    }

    private var selectedAdapter: AgentAdapterDescriptor? {
        model.availableAgents.first(where: { $0.kind == selectedKind })
    }

    private func launch(
        _ adapter: AgentAdapterDescriptor,
        resumeSessionID: String?
    ) async {
        do {
            try await model.launch(
                adapter,
                resumeSessionID: resumeSessionID
            )
        } catch {
            model.lastError = error.localizedDescription
        }
    }
}

private struct NoteAgentNativeTerminalView: NSViewRepresentable {
    @Environment(\.retainedPageIsActive) private var retainedPageIsActive
    let engine: any TerminalViewProviding
    let terminalID: NoteAgentTerminalID
    let shortcutPolicy: TerminalShortcutPolicy

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        host.shortcutPolicy = shortcutPolicy
        host.breathShortcutMatch = Self.shortcutMatch
        host.handleTerminalShortcut = { event in
            _ = engine.handleShortcutKeyDown(event, for: terminalID)
        }
        host.isHidden = !retainedPageIsActive
        host.install(
            engine.view(for: terminalID),
            placeholder: "Agent 终端正在启动…"
        )
        return host
    }

    func updateNSView(
        _ nsView: TerminalHostView,
        context: Context
    ) {
        nsView.shortcutPolicy = shortcutPolicy
        nsView.breathShortcutMatch = Self.shortcutMatch
        nsView.handleTerminalShortcut = { event in
            _ = engine.handleShortcutKeyDown(event, for: terminalID)
        }
        nsView.isHidden = !retainedPageIsActive
        nsView.install(
            engine.view(for: terminalID),
            placeholder: "Agent 终端正在启动…"
        )
    }

    private static func shortcutMatch(
        _ event: NSEvent
    ) -> BreathShortcutMatch? {
        if let match = BreathShortcutCatalog.match(for: event) {
            return match
        }
        if GitShortcutResolver.commandID(
            matching: event,
            preferences: GitPreferencesStore.shared.preferences,
            requiredScope: .global
        ) != nil {
            return .application
        }
        return nil
    }
}

private struct NoteConflictComparison: View {
    let document: NoteDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("外部修改比较")
                    .font(.headline)
                Spacer()
                Button("完成") { dismiss() }
            }
            .padding()
            Divider()
            HSplitView {
                comparisonColumn(title: "我的版本", content: document.content)
                comparisonColumn(title: "磁盘版本", content: diskContent)
            }
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private var diskContent: String {
        if case let .conflict(content) = document.externalState {
            return content
        }
        return ""
    }

    private func comparisonColumn(
        title: String,
        content: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(8)
            Divider()
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
        }
        .frame(minWidth: 320)
    }
}
