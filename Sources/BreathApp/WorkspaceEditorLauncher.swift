import AppKit
import SwiftUI

@MainActor
struct WorkspaceEditorLauncher: View {
    let workspacePath: String
    let barHeight: CGFloat

    @AppStorage("preferredWorkspaceEditorID") private var preferredEditorID = ""
    @Environment(\.applicationLanguage) private var applicationLanguage
    @State private var installedEditors: [InstalledWorkspaceEditor] = []
    @State private var openError: String?

    var body: some View {
        HStack(spacing: 0) {
            if let selectedEditor {
                Button {
                    openWorkspace(in: selectedEditor)
                } label: {
                    HStack(spacing: 5) {
                        editorIcon(selectedEditor)
                        Text(selectedEditor.displayName)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: barHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(workspacePath.isEmpty)
                .help(localizer.format("使用 %@ 打开工作区", selectedEditor.displayName))
                .accessibilityLabel(
                    localizer.format("使用 %@ 打开工作区", selectedEditor.displayName)
                )

                Divider()
                    .frame(height: 12)

                Menu {
                    ForEach(installedEditors) { editor in
                        Button {
                            preferredEditorID = editor.id
                        } label: {
                            if editor.id == selectedEditor.id {
                                Label(editor.displayName, systemImage: "checkmark")
                            } else {
                                Text(editor.displayName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(
                            width: 20,
                            height: barHeight
                        )
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(localizer.string("选择编辑器"))
                .accessibilityLabel(localizer.string("选择编辑器"))
            } else {
                Label(localizer.string("未找到编辑器"), systemImage: "square.and.pencil")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .onAppear(perform: reloadInstalledEditors)
        .alert(
            localizer.string("无法打开编辑器"),
            isPresented: openErrorPresented
        ) {
            Button(localizer.string("好")) {
                openError = nil
            }
        } message: {
            Text(openError ?? localizer.string("未知错误"))
        }
    }

    private var selectedEditor: InstalledWorkspaceEditor? {
        WorkspaceEditorSelection().selectedEditor(
            preferredID: preferredEditorID,
            from: installedEditors
        )
    }

    private var openErrorPresented: Binding<Bool> {
        Binding(
            get: { openError != nil },
            set: { isPresented in
                if !isPresented {
                    openError = nil
                }
            }
        )
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: applicationLanguage)
    }

    private func editorIcon(_ editor: InstalledWorkspaceEditor) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: editor.applicationURL.path))
            .resizable()
            .interpolation(.high)
            .frame(width: 13, height: 13)
            .accessibilityHidden(true)
    }

    private func reloadInstalledEditors() {
        installedEditors = WorkspaceEditorCatalog.common.installedEditors {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
        if let selectedEditor, selectedEditor.id != preferredEditorID {
            preferredEditorID = selectedEditor.id
        }
    }

    private func openWorkspace(in editor: InstalledWorkspaceEditor) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)

        NSWorkspace.shared.open(
            [workspaceURL],
            withApplicationAt: editor.applicationURL,
            configuration: configuration
        ) { _, error in
            guard let error else { return }
            Task { @MainActor in
                openError = error.localizedDescription
            }
        }
    }
}
