import Foundation
import Testing

@Suite("Explanation presentation")
struct ExplanationPresentationTests {
    @Test("static explanatory copy uses hover help instead of visible text")
    func staticExplanationsUseHoverHelp() throws {
        let settings = try compactSource("BreathSettingsView.swift")
        let workbench = try compactSource("WorkbenchView.swift")
        let skills = try compactSource("SkillManagementSheets.swift")
        let git = try compactSource("GitWorkbenchView.swift")

        expectHoverHelp(
            [
                "选择终端聚焦时，由Breath还是终端内应用优先获得冲突快捷键。",
                "列出Breath会话分支与托管目录。仅剩分支、目录残留和未关联会话的检出目录会继续占用本地资源。",
            ],
            in: settings
        )
        expectHoverHelp(
            [
                "将Worktree分支合并到所选本地分支。只会合并已提交内容；不会删除源Worktree。若发生冲突，Breath会自动中止合并。",
            ],
            in: workbench
        )
        expectHoverHelp(
            [
                "ZIP可以包含一个或多个Skill；导入前不会执行其中的脚本。",
                "仅支持无需认证的公开GitHubRepo；私有Repo请改用ZIP。",
                "只会安装你明确选择的候选Skill。",
                "每次安装默认不选择任何Agent。每个目标将获得完整独立副本。",
                "新的或重启后的Agent会话可能才会加载变更；Breath没有停止任何运行中会话。",
                "本地已修改，默认不选择",
                "更新后该链接会变成此Agent的独立实体目录",
                "只会从明确选择的Agent中移除Skill。",
                "移入macOS废纸篓，可恢复",
                "只移除链接，共享目标保持不变",
            ],
            in: skills
        )
        expectHoverHelp(
            [
                "将分别提交%d个Root，不保证跨Root原子性",
                "凭证只传递给当前Git进程，Breath不会保存。",
                "安全快照是尽力而为的本地缓存，不是连续LocalHistory。",
                "拖动提交可重新排序；受保护或已发布历史会被安全规则阻止。",
                "选择%@要跟踪的远程分支。",
                "大小：%d字节，可使用系统预览。",
                "大小：%d字节；为保持页面响应，未自动生成文本Diff。",
            ],
            in: git
        )

        #expect(!git.contains("description:Text("))
    }

    @Test("info help uses 300ms plain tooltips while control help remains native")
    func hoverHelpIsConsistentAccessibleAndDocumented() throws {
        let component = try source("ExplanationHelp.swift")
        let compactComponent = component.filter { !$0.isWhitespace }
        #expect(component.contains("Task.sleep(for: .milliseconds(300))"))
        #expect(component.contains("NSPanel("))
        #expect(!component.contains(".popover("))
        #expect(component.contains(".hoverTooltip(explanation)"))
        #expect(component.contains("below anchorRect: NSRect"))
        #expect(
            component.contains(
                "anchorRect.minY - size.height - Self.anchorGap"
            )
        )
        #expect(component.contains("TooltipBubble(text: text, width: width)"))
        #expect(!component.contains("// TEMP DEBUG"))
        #expect(component.contains(".accessibilityHint(explanation)"))
        #expect(component.contains("struct ExplanationLabel"))
        #expect(!component.contains("struct ExplanationHelp"))
        #expect(
            compactComponent.contains(
                "HStack(spacing:4){content.accessibilityHint(explanation)"
                    + "Image(systemName:\"info.circle\")"
            )
        )
        #expect(
            compactComponent.contains(
                ".accessibilityHidden(true).hoverTooltip(explanation)"
                    + "}.fixedSize(horizontal:true,vertical:false)"
            )
        )
        #expect(
            !compactComponent.contains(
                ".fixedSize(horizontal:true,vertical:false).hoverTooltip(explanation)"
            )
        )

        let sourcesDirectory = packageRoot
            .appendingPathComponent("Sources/BreathApp", isDirectory: true)
        let sourceURLs = try FileManager.default.contentsOfDirectory(
            at: sourcesDirectory,
            includingPropertiesForKeys: nil
        )
        for sourceURL in sourceURLs where sourceURL.pathExtension == "swift" {
            let fileSource = try String(contentsOf: sourceURL, encoding: .utf8)
            if sourceURL.lastPathComponent != "ExplanationHelp.swift" {
                #expect(!fileSource.contains(".hoverTooltip("))
                #expect(!fileSource.contains("Image(systemName: \"info.circle\")"))
            }
        }

        let workbench = try source("WorkbenchView.swift")
        #expect(workbench.contains(".help(localizer.string(\"工作区菜单\"))"))
        let git = try source("GitWorkbenchView.swift")
        #expect(git.contains(".help(shortcutHelp(title: title, commandID: shortcutID))"))

        let root = packageRoot
        let guidelines = try String(
            contentsOf: root.appendingPathComponent(
                "docs/design/interface-guidelines.md"
            ),
            encoding: .utf8
        )
        #expect(guidelines.contains("静态解释文字，不得作为正文、页脚或空状态描述直接展示"))
        #expect(guidelines.contains("统一放在 `info.circle` 信息图标的悬浮提示中"))
        #expect(guidelines.contains("解释提示统一在指针停留 300ms 后出现"))
        #expect(
            guidelines.contains("不使用系统 Popover 的液态玻璃样式")
        )
        #expect(guidelines.contains("`info.circle` 不得单独、悬空展示"))
        #expect(guidelines.contains("组成同一个 `ExplanationLabel`"))
        #expect(guidelines.contains("以该图标作为弹出锚点"))
        #expect(guidelines.contains("继续使用系统原生 `.help`"))
    }

    private func expectHoverHelp(
        _ explanations: [String],
        in compactSource: String
    ) {
        for explanation in explanations {
            let range = compactSource.range(of: explanation)
            #expect(range != nil, "Missing explanatory copy: \(explanation)")
            #expect(compactSource.contains("ExplanationLabel("))
            #expect(!compactSource.contains("ExplanationHelp("))
        }
    }

    private func compactSource(_ name: String) throws -> String {
        try source(name).filter { !$0.isWhitespace }
    }

    private func source(_ name: String) throws -> String {
        try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources/BreathApp")
                .appendingPathComponent(name),
            encoding: .utf8
        )
    }

    private var packageRoot: URL {
        URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    }
}
