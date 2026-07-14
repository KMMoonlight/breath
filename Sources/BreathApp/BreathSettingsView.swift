import BreathAgents
import BreathCore
import SwiftUI

struct BreathSettingsView: View {
    @ObservedObject var model: BreathApplicationModel
    @State private var archiveToDelete: WorkSession?

    var body: some View {
        TabView {
            Form {
                Picker("外观", selection: applicationAppearance) {
                    Text("跟随系统").tag(ApplicationAppearance.system)
                    Text("浅色").tag(ApplicationAppearance.light)
                    Text("深色").tag(ApplicationAppearance.dark)
                }
                Picker("侧边栏密度", selection: sidebarDensity) {
                    Text("舒适").tag(SidebarDensity.comfortable)
                    Text("紧凑").tag(SidebarDensity.compact)
                }
                Text("这里只控制终端之外的 Breath 界面。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .tabItem { Label("应用配置", systemImage: "paintbrush") }

            Form {
                TextField("字体（不可用时使用 Menlo）", text: terminalFontFamily)
                Stepper(value: terminalFontSize, in: 9...32, step: 1) {
                    Text("字号：\(model.settings.terminal.fontSize, specifier: "%.0f")")
                }
                Picker("颜色主题", selection: terminalColorTheme) {
                    Text("深色").tag(TerminalColorTheme.dark)
                    Text("浅色").tag(TerminalColorTheme.light)
                    Text("Solarized Dark").tag(TerminalColorTheme.solarizedDark)
                }
                Picker("光标", selection: terminalCursorStyle) {
                    Text("方块").tag(TerminalCursorStyle.block)
                    Text("竖线").tag(TerminalCursorStyle.bar)
                    Text("下划线").tag(TerminalCursorStyle.underline)
                }
                Text("终端配置只改变终端内部样式，不读取或同步 Ghostty 配置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .tabItem { Label("终端配置", systemImage: "terminal") }

            List(model.adapters, id: \.kind) { adapter in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(adapter.displayName)
                        Text(integrationDescription(adapter))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(adapter.userConfigurationPath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: integrationBinding(adapter))
                        .labelsHidden()
                }
                .padding(.vertical, 3)
            }
            .padding(12)
            .tabItem { Label("Agent 集成", systemImage: "point.3.connected.trianglepath.dotted") }

            Group {
                if model.snapshot.archivedWorkSessions.isEmpty {
                    ContentUnavailableView(
                        "没有已归档会话",
                        systemImage: "archivebox"
                    )
                } else {
                    List(model.snapshot.archivedWorkSessions) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.title)
                                Text(workspaceName(for: session))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("恢复") {
                                model.restoreArchive(session.id)
                            }
                            Button("永久删除", role: .destructive) {
                                archiveToDelete = session
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .padding(12)
            .tabItem { Label("已归档", systemImage: "archivebox") }
        }
        .frame(width: 650, height: 440)
        .alert("永久删除归档？", isPresented: deleteAlertPresented, presenting: archiveToDelete) { session in
            Button("取消", role: .cancel) { archiveToDelete = nil }
            Button("永久删除", role: .destructive) {
                model.deleteArchive(session.id)
                archiveToDelete = nil
            }
        } message: { _ in
            Text("只会删除 Breath 元数据，不会删除项目文件或 Agent CLI 自己保存的会话。")
        }
    }

    private var applicationAppearance: Binding<ApplicationAppearance> {
        Binding(
            get: { model.settings.application.appearance },
            set: { value in
                var settings = model.settings.application
                settings.appearance = value
                model.saveApplicationSettings(settings)
            }
        )
    }

    private var sidebarDensity: Binding<SidebarDensity> {
        Binding(
            get: { model.settings.application.sidebarDensity },
            set: { value in
                var settings = model.settings.application
                settings.sidebarDensity = value
                model.saveApplicationSettings(settings)
            }
        )
    }

    private var terminalFontFamily: Binding<String> {
        terminalBinding(\.fontFamily)
    }

    private var terminalFontSize: Binding<Double> {
        terminalBinding(\.fontSize)
    }

    private var terminalColorTheme: Binding<TerminalColorTheme> {
        terminalBinding(\.colorTheme)
    }

    private var terminalCursorStyle: Binding<TerminalCursorStyle> {
        terminalBinding(\.cursorStyle)
    }

    private func terminalBinding<Value>(
        _ keyPath: WritableKeyPath<TerminalSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.settings.terminal[keyPath: keyPath] },
            set: { value in
                var settings = model.settings.terminal
                settings[keyPath: keyPath] = value
                model.saveTerminalSettings(settings)
            }
        )
    }

    private func integrationBinding(_ adapter: AgentAdapterDescriptor) -> Binding<Bool> {
        Binding(
            get: { model.enabledAgents.contains(adapter.kind) },
            set: { model.setAgentIntegration(adapter, enabled: $0) }
        )
    }

    private func integrationDescription(_ adapter: AgentAdapterDescriptor) -> String {
        switch adapter.integrationMechanism {
        case .userHooks: "用户级 Hooks · 最低兼容 \(adapter.minimumVersion)"
        case .plugin: "用户级 Plugin · 最低兼容 \(adapter.minimumVersion)"
        case .extension: "用户级 Extension · 最低兼容 \(adapter.minimumVersion)"
        case .terminalParsing: "终端输出解析"
        }
    }

    private func workspaceName(for session: WorkSession) -> String {
        model.snapshot.workspaces.first(where: { $0.id == session.workspaceID })?
            .displayName ?? "工作区已移除"
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { archiveToDelete != nil },
            set: { if !$0 { archiveToDelete = nil } }
        )
    }
}
