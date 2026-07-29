import AppKit
import BreathAgents
import BreathAutomation
import BreathCore
import BreathUpdates
import Darwin
import SwiftUI

@main
enum BreathMain {
    @MainActor
    static func main() {
#if DEBUG
        if CommandLine.arguments.dropFirst().first == "--verify-split-view-responder-chain" {
            exit(SplitViewResponderChainVerifier.run())
        }
        if CommandLine.arguments.dropFirst().first == "--verify-quiet-empty-states" {
            let resultURL: URL? = CommandLine.arguments.firstIndex(of: "--result-file").flatMap { index in
                let pathIndex = CommandLine.arguments.index(after: index)
                guard pathIndex < CommandLine.arguments.endIndex else { return nil }
                return URL(fileURLWithPath: CommandLine.arguments[pathIndex])
            }
            exit(AppShellEmptyStateVerifier.run(resultURL: resultURL))
        }
#endif
        if CommandLine.arguments.dropFirst().first == "--agent-hook" {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let command = AgentHookCommand()
            _ = command.run(
                arguments: CommandLine.arguments,
                environment: ProcessInfo.processInfo.environment,
                standardInput: input
            )
            if let output = command.standardOutput(
                arguments: CommandLine.arguments
            ) {
                FileHandle.standardOutput.write(output)
            }
            return
        }
        if CommandLine.arguments.dropFirst().first == "trigger" {
            let exitCode = AutomationTriggerCommand().run(
                arguments: Array(CommandLine.arguments.dropFirst()),
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                standardOutput: { message in
                    FileHandle.standardOutput.write(Data("\(message)\n".utf8))
                },
                standardError: { message in
                    FileHandle.standardError.write(Data("\(message)\n".utf8))
                }
            )
            exit(exitCode)
        }
        _ = NSApplication.shared.setActivationPolicy(.regular)
        BreathDesktopApp.main()
    }
}

#if DEBUG
@MainActor
private enum SplitViewResponderChainVerifier {
    static func run() -> Int32 {
        let selector = NSSelectorFromString("toggleSidebar:")
        let splitViews: [NSSplitView] = [
            NativeSplitNSView(frame: .zero),
            GitThreeColumnNSView(frame: .zero),
        ]
        return splitViews.allSatisfy { !$0.responds(to: selector) }
            ? EXIT_SUCCESS
            : EXIT_FAILURE
    }
}
#endif

private struct BreathDesktopApp: App {
    @NSApplicationDelegateAdaptor(BreathAppDelegate.self) private var appDelegate
    @StateObject private var model = BreathApplicationModel.makeDefault()
    @StateObject private var gitPreferencesStore = GitPreferencesStore.shared
    private let updateController = BreathUpdateController()

    var body: some Scene {
        Window("Breath", id: "main") {
            WorkbenchView(model: model)
                .preferredColorScheme(preferredColorScheme)
                .applicationLanguage(model.settings.application.language)
                .tint(.primary)
                .onAppear {
                    appDelegate.model = model
                    model.start()
                }
        }
        .defaultSize(width: 1240, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                OpenMainWindowCommand(
                    language: model.settings.application.language
                )
                Button(localizer.string("新建工作会话")) {
                    guard let workspaceID = model.currentWorkspaceID else { return }
                    model.createWorkSession(in: workspaceID)
                }
                .breathKeyboardShortcut(
                    BreathShortcutCatalog.newWorkSession,
                    priority: model.shortcutPriority
                )
                .disabled(!model.canPerformCommands || model.currentWorkspaceID == nil)

                Divider()

                Button(localizer.string("关闭当前分屏或工作会话")) {
                    NotificationCenter.default.post(
                        name: .breathCloseTerminalTarget,
                        object: nil
                    )
                }
                .breathKeyboardShortcut(
                    BreathShortcutCatalog.closePane,
                    priority: model.shortcutPriority
                )
                .disabled(
                    !model.canPerformCommands
                        || model.snapshot.selectedWorkSessionID == nil
                )
            }
            CommandMenu(localizer.string("导航")) {
                ForEach(BreathShortcutCatalog.workSessionTabs) { tab in
                    Button(
                        localizer.format("切换到会话 Tab %d", tab.displayNumber)
                    ) {
                        NotificationCenter.default.post(
                            name: .breathSelectWorkSessionTab,
                            object: tab
                        )
                    }
                    .breathKeyboardShortcut(
                        tab.shortcut,
                        priority: model.shortcutPriority
                    )
                    .disabled(
                        !model.canPerformCommands
                            || !model.canSelectWorkSessionTab(at: tab.selectionIndex)
                    )
                }

                Divider()

                Button(localizer.string("上一个分屏")) {
                    NotificationCenter.default.post(
                        name: .breathSelectPreviousPane,
                        object: nil
                    )
                }
                .breathKeyboardShortcut(
                    BreathShortcutCatalog.previousPane,
                    priority: model.shortcutPriority
                )
                .disabled(!model.canPerformCommands || !model.canNavigateSplitPanes)

                Button(localizer.string("下一个分屏")) {
                    NotificationCenter.default.post(
                        name: .breathSelectNextPane,
                        object: nil
                    )
                }
                .breathKeyboardShortcut(
                    BreathShortcutCatalog.nextPane,
                    priority: model.shortcutPriority
                )
                .disabled(!model.canPerformCommands || !model.canNavigateSplitPanes)
            }
            CommandGroup(replacing: .appSettings) {
                OpenSettingsPageCommand(
                    language: model.settings.application.language,
                    shortcutPriority: model.shortcutPriority
                )
            }
            CommandGroup(after: .appInfo) {
                Button(localizer.string("检查更新…")) {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.configuration.isReady)
            }
            CommandMenu(localizer.string("Git")) {
                Button(localizer.string("打开 Git 工作台")) {
                    NotificationCenter.default.post(
                        name: .breathOpenGitWorkbench,
                        object: nil
                    )
                }
                .gitKeyboardShortcut(
                    "git.open",
                    preferences: gitPreferencesStore.preferences,
                    requiredScope: .global
                )

                Divider()

                Button(localizer.string("Commit")) {
                    NotificationCenter.default.post(
                        name: .breathGitCommit,
                        object: nil
                    )
                }
                .gitKeyboardShortcut(
                    "git.commit",
                    preferences: gitPreferencesStore.preferences,
                    requiredScope: .global
                )
                .disabled(model.currentWorkspaceID == nil)

                Button(localizer.string("Push")) {
                    NotificationCenter.default.post(
                        name: .breathGitPush,
                        object: nil
                    )
                }
                .gitKeyboardShortcut(
                    "git.push",
                    preferences: gitPreferencesStore.preferences,
                    requiredScope: .global
                )
                .disabled(model.currentWorkspaceID == nil)
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.settings.application.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var localizer: ApplicationLocalizer {
        ApplicationLocalizer(language: model.settings.application.language)
    }
}

private struct OpenMainWindowCommand: View {
    let language: ApplicationLanguage
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(ApplicationLocalizer(language: language).string("打开主窗口")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct OpenSettingsPageCommand: View {
    let language: ApplicationLanguage
    let shortcutPriority: BreathShortcutPriority
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(ApplicationLocalizer(language: language).string("设置…")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .breathOpenSettings,
                    object: nil
                )
            }
        }
        .breathKeyboardShortcut(
            BreathShortcutCatalog.openSettings,
            priority: shortcutPriority
        )
    }
}

@MainActor
private final class BreathAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: BreathApplicationModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        if let iconURL = BreathResources.bundle.url(
            forResource: "AppIcon",
            withExtension: "png"
        ) {
            NSApplication.shared.applicationIconImage = NSImage(
                contentsOf: iconURL
            )
        }
#endif
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.repairDetectedAgentIntegrations()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc
    private func workspaceDidWake(_ notification: Notification) {
        model?.resumeAutomationSchedulesAfterWake()
    }

    @objc
    private func workspaceWillSleep(_ notification: Notification) {
        model?.suspendAutomationSchedulesForSleep()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let localizer = ApplicationLocalizer(
            language: model?.settings.application.language ?? .system
        )
        let alert = NSAlert()
        alert.messageText = localizer.string("退出 Breath？")
        if model?.hasActiveAutomationRuns == true {
            alert.informativeText = localizer.string(
                "Breath 会保存布局，取消已排队的自动化，中断正在运行的自动化，并停止所有终端进程。"
            )
        } else {
            alert.informativeText = localizer.string(
                "Breath 会先保存布局、最后选择和 Agent 会话标识，再停止所有终端进程。"
            )
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: localizer.string("退出"))
        alert.addButton(withTitle: localizer.string("取消"))
        switch model?.settings.application.appearance {
        case .dark:
            alert.window.appearance = NSAppearance(named: .darkAqua)
        case .light:
            alert.window.appearance = NSAppearance(named: .aqua)
        case .system, nil:
            alert.window.appearance = sender.keyWindow?.effectiveAppearance
        }
        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }
        guard let model else {
            return .terminateNow
        }
        Task { @MainActor in
            await GitOperationRegistry.shared.prepareForTermination()
            let ready = await model.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: ready)
        }
        return .terminateLater
    }
}
