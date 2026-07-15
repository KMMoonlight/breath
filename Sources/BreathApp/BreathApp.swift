import AppKit
import BreathAgents
import BreathCore
import BreathUpdates
import Darwin
import SwiftUI

@main
enum BreathMain {
    @MainActor
    static func main() {
#if DEBUG
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
            _ = AgentHookCommand().run(
                arguments: CommandLine.arguments,
                environment: ProcessInfo.processInfo.environment,
                standardInput: input
            )
            return
        }
        BreathDesktopApp.main()
    }
}

private struct BreathDesktopApp: App {
    @NSApplicationDelegateAdaptor(BreathAppDelegate.self) private var appDelegate
    @StateObject private var model = BreathApplicationModel.makeDefault()
    private let updateController = BreathUpdateController()

    var body: some Scene {
        Window("Breath", id: "main") {
            WorkbenchView(model: model)
                .preferredColorScheme(preferredColorScheme)
                .tint(.indigo)
                .onAppear {
                    appDelegate.model = model
                    model.start()
                }
        }
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                OpenMainWindowCommand()
            }
            CommandGroup(after: .appInfo) {
                Button("检查更新…") {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.configuration.isReady)
            }
        }

        Settings {
            BreathSettingsView(model: model)
                .preferredColorScheme(preferredColorScheme)
                .tint(.indigo)
                .onAppear {
                    appDelegate.model = model
                    model.start()
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
}

private struct OpenMainWindowCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开主窗口") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("n", modifiers: [.command])
    }
}

@MainActor
private final class BreathAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: BreathApplicationModel?

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
        let alert = NSAlert()
        alert.messageText = "退出 Breath？"
        alert.informativeText = "Breath 会先保存布局、最后选择和 Agent 会话标识，再停止所有终端进程。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }
        guard let model else {
            return .terminateNow
        }
        Task { @MainActor in
            let ready = await model.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: ready)
        }
        return .terminateLater
    }
}
