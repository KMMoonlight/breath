import BreathCore
import SwiftUI

struct GitDiffView: View {
    let workspace: Workspace
    let fontSize: CGFloat
    let onClose: () -> Void

    @Environment(\.applicationLanguage) private var applicationLanguage
    @Environment(\.colorScheme) private var colorScheme
    @State private var files: [GitChangedFile] = []
    @State private var fileTree: [GitChangedFileTreeNode] = []
    @State private var expandedDirectoryIDs: Set<String> = []
    @State private var selectedFileID: GitChangedFile.ID?
    @State private var isLoadingFiles = true
    @State private var diffState = GitFileDiffState.idle
    @State private var diffReloadID = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                changedFileList
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
                Divider()
                selectedFileDiff
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: workspace.path) {
            await loadFiles()
        }
        .task(id: GitFileDiffRequestID(
            fileID: selectedFileID,
            reloadID: diffReloadID
        )) {
            await loadSelectedFileDiff()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Label(
                    localizer.string("返回终端"),
                    systemImage: "chevron.left"
                )
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 16)

            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(workspace.displayName)
                .lineLimit(1)
            Text(localizer.string("Git 变更"))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                Task { await loadFiles() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(localizer.string("刷新 Git 变更"))
            .disabled(isLoadingFiles)
        }
        .font(.system(size: fontSize))
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.bar)
    }

    @ViewBuilder
    private var changedFileList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(localizer.string("变更文件"))
                    .fontWeight(.semibold)
                if !isLoadingFiles {
                    Text("\(files.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: fontSize))
            .padding(.horizontal, 12)
            .frame(height: 34)

            Divider()

            if isLoadingFiles {
                ProgressView(localizer.string("正在读取 Git 变更…"))
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if files.isEmpty {
                BreathEmptyState(
                    title: localizer.string("暂无 Git 变更"),
                    systemImage: "checkmark.circle"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(visibleFileTreeRows) { row in
                            if let file = row.node.file {
                                changedFileRow(file, depth: row.depth)
                            } else {
                                changedFileDirectoryRow(row)
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func changedFileDirectoryRow(
        _ row: GitChangedFileTreeRow
    ) -> some View {
        let isExpanded = expandedDirectoryIDs.contains(row.node.id)
        return Button {
            if isExpanded {
                expandedDirectoryIDs.remove(row.node.id)
            } else {
                expandedDirectoryIDs.insert(row.node.id)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10)
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor)
                Text(row.node.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .font(.system(size: fontSize))
            .padding(.leading, treeIndent(for: row.depth))
            .padding(.trailing, 7)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func changedFileRow(
        _ file: GitChangedFile,
        depth: Int
    ) -> some View {
        Button {
            selectedFileID = file.id
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Text(file.kind.rawValue)
                    .fontWeight(.semibold)
                    .foregroundStyle(color(for: file.kind))
                    .frame(width: 14, alignment: .center)
                Text(URL(fileURLWithPath: file.path).lastPathComponent)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .font(.system(size: fontSize))
            .padding(.leading, treeIndent(for: depth))
            .padding(.trailing, 7)
            .frame(height: 26)
            .background {
                if selectedFileID == file.id {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(0.18))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectedFileDiff: some View {
        if let selectedFile {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(selectedFile.kind.rawValue)
                        .fontWeight(.semibold)
                        .foregroundStyle(color(for: selectedFile.kind))
                    Text(selectedFile.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .font(.system(size: fontSize))
                .padding(.horizontal, 12)
                .frame(height: 34)

                Divider()

                diffContent
            }
        } else {
            BreathEmptyState(
                title: localizer.string("请选择一个文件查看 Diff"),
                style: .passive
            )
        }
    }

    @ViewBuilder
    private var diffContent: some View {
        switch diffState {
        case .idle, .loading:
            ProgressView(localizer.string("正在读取 Diff…"))
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let lines):
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            diffLineRow(
                                line,
                                filePath: selectedFile?.path ?? ""
                            )
                            .frame(
                                minWidth: geometry.size.width,
                                alignment: .leading
                            )
                        }
                    }
                    .frame(
                        minWidth: geometry.size.width,
                        minHeight: geometry.size.height,
                        alignment: .topLeading
                    )
                    .textSelection(.enabled)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        case .unavailable:
            BreathEmptyState(
                title: localizer.string("无法读取 Git Diff"),
                systemImage: "exclamationmark.triangle"
            )
        }
    }

    private func diffLineRow(
        _ line: GitDiffLine,
        filePath: String
    ) -> some View {
        HStack(spacing: 0) {
            diffLineNumber(line.oldLineNumber)
            diffLineNumber(line.newLineNumber)
            Text(diffMarker(for: line.kind))
                .foregroundStyle(diffMarkerColor(for: line.kind))
                .frame(width: 20, alignment: .center)
            Text(highlightedContent(for: line, filePath: filePath))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 12)
        }
        .font(
            .system(
                size: max(10, fontSize - 1),
                design: .monospaced
            )
        )
        .frame(height: 20)
        .background(diffBackgroundColor(for: line.kind))
    }

    private func diffLineNumber(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .padding(.trailing, 6)
            .frame(width: 42, height: 20, alignment: .trailing)
            .background(Color.primary.opacity(0.025))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 1)
            }
    }

    private func highlightedContent(
        for line: GitDiffLine,
        filePath: String
    ) -> AttributedString {
        guard line.kind == .context
                || line.kind == .addition
                || line.kind == .deletion
        else {
            var text = AttributedString(line.content)
            text.foregroundColor = diffTextColor(for: line.kind)
            return text
        }

        var highlighted = AttributedString()
        for token in GitCodeSyntaxHighlighter().tokens(
            in: line.content,
            filePath: filePath
        ) {
            var text = AttributedString(token.text)
            text.foregroundColor = syntaxColor(for: token.kind)
            highlighted.append(text)
        }
        return highlighted
    }

    private var visibleFileTreeRows: [GitChangedFileTreeRow] {
        visibleFileTreeRows(in: fileTree, depth: 0)
    }

    private func visibleFileTreeRows(
        in nodes: [GitChangedFileTreeNode],
        depth: Int
    ) -> [GitChangedFileTreeRow] {
        nodes.flatMap { node in
            var rows = [GitChangedFileTreeRow(node: node, depth: depth)]
            if node.isDirectory,
               expandedDirectoryIDs.contains(node.id)
            {
                rows.append(
                    contentsOf: visibleFileTreeRows(
                        in: node.children,
                        depth: depth + 1
                    )
                )
            }
            return rows
        }
    }

    private func directoryIDs(
        in nodes: [GitChangedFileTreeNode]
    ) -> Set<String> {
        nodes.reduce(into: Set<String>()) { result, node in
            guard node.isDirectory else { return }
            result.insert(node.id)
            result.formUnion(directoryIDs(in: node.children))
        }
    }

    private func treeIndent(for depth: Int) -> CGFloat {
        7 + CGFloat(depth) * 16
    }

    private func diffMarker(for kind: GitDiffLineKind) -> String {
        switch kind {
        case .addition: "+"
        case .deletion: "−"
        case .marker: "\\"
        case .metadata, .hunk, .context: ""
        }
    }

    private func diffMarkerColor(for kind: GitDiffLineKind) -> Color {
        switch kind {
        case .addition: .green
        case .deletion: .red
        case .hunk: .blue
        case .metadata, .context, .marker: .secondary
        }
    }

    private func diffBackgroundColor(for kind: GitDiffLineKind) -> Color {
        let isDark = colorScheme == .dark
        switch kind {
        case .addition:
            return .green.opacity(isDark ? 0.14 : 0.10)
        case .deletion:
            return .red.opacity(isDark ? 0.14 : 0.09)
        case .hunk:
            return .blue.opacity(isDark ? 0.15 : 0.09)
        case .marker:
            return .orange.opacity(isDark ? 0.08 : 0.05)
        case .metadata:
            return Color.primary.opacity(isDark ? 0.035 : 0.025)
        case .context:
            return .clear
        }
    }

    private func diffTextColor(for kind: GitDiffLineKind) -> Color {
        switch kind {
        case .hunk: .blue
        case .metadata, .marker: .secondary
        case .addition, .deletion, .context: .primary
        }
    }

    private func syntaxColor(for kind: GitCodeTokenKind) -> Color {
        switch kind {
        case .plain: .primary
        case .keyword: Color(nsColor: .systemPurple)
        case .type: Color(nsColor: .systemTeal)
        case .string: Color(nsColor: .systemGreen)
        case .number: Color(nsColor: .systemOrange)
        case .comment: .secondary
        }
    }

    private var selectedFile: GitChangedFile? {
        files.first { $0.id == selectedFileID }
    }

    private func loadFiles() async {
        isLoadingFiles = true
        let nextFiles = await GitDiffReader().changedFiles(at: workspace.path)
        guard !Task.isCancelled else { return }

        let nextFileTree = GitChangedFileTreeBuilder().build(nextFiles)
        let previousDirectoryIDs = directoryIDs(in: fileTree)
        let nextDirectoryIDs = directoryIDs(in: nextFileTree)
        var nextExpandedDirectoryIDs = expandedDirectoryIDs
        nextExpandedDirectoryIDs.formIntersection(nextDirectoryIDs)
        nextExpandedDirectoryIDs.formUnion(
            nextDirectoryIDs.subtracting(previousDirectoryIDs)
        )

        files = nextFiles
        fileTree = nextFileTree
        expandedDirectoryIDs = nextExpandedDirectoryIDs
        if let selectedFileID,
           nextFiles.contains(where: { $0.id == selectedFileID })
        {
            self.selectedFileID = selectedFileID
        } else {
            selectedFileID = nextFiles.first?.id
        }
        if nextFiles.isEmpty {
            diffState = .idle
        }
        diffReloadID += 1
        isLoadingFiles = false
    }

    private func loadSelectedFileDiff() async {
        guard let selectedFile else {
            diffState = .idle
            return
        }
        let requestedFileID = selectedFile.id
        diffState = .loading
        let diff = await GitDiffReader().diff(
            for: selectedFile,
            at: workspace.path
        )
        guard !Task.isCancelled, selectedFileID == requestedFileID else { return }
        diffState = diff.map {
            .loaded(GitUnifiedDiffParser().parse($0))
        } ?? .unavailable
    }

    private func color(for kind: GitChangedFileKind) -> Color {
        switch kind {
        case .added: .green
        case .modified: .orange
        case .deleted: .red
        case .untracked: .secondary
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }
}

private enum GitFileDiffState: Equatable {
    case idle
    case loading
    case loaded([GitDiffLine])
    case unavailable
}

private struct GitFileDiffRequestID: Equatable {
    let fileID: GitChangedFile.ID?
    let reloadID: Int
}

private struct GitChangedFileTreeRow: Identifiable {
    let node: GitChangedFileTreeNode
    let depth: Int

    var id: String { node.id }
}
