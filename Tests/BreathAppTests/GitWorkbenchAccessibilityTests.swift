import Foundation
import Testing

@Suite("Git workbench accessibility")
struct GitWorkbenchAccessibilityTests {
    @Test("workbench exposes keyboard, status, graph, diff, and resize semantics")
    func exposesStableSemantics() throws {
        let source = try sourceFile("Sources/BreathApp/GitWorkbenchView.swift")
        let shell = try sourceFile("Sources/BreathApp/WorkbenchView.swift")

        for semantic in [
            "Git 工作台",
            "Git Root",
            "本地变更工作流",
            "Commit Graph",
            "按时间和拓扑顺序列出提交，可使用方向键浏览",
            "拓扑顺序，%d 个父提交",
            "选择此修改行",
            "Git 命令与结果",
            "调整 Git 列宽",
            "调整 Git Console 高度",
        ] {
            #expect(source.contains(semantic))
        }
        #expect(source.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(source.contains(".accessibilityLabel(accessibilityLabel(line))"))
        #expect(source.contains("operationStatusLabel(record.status)"))
        #expect(shell.contains(".font(applicationFont(for: model))"))
    }

    @Test("every configured default shortcut has an in-scope command surface")
    func routesDefaultShortcuts() throws {
        let sources = try [
            "Sources/BreathApp/BreathApp.swift",
            "Sources/BreathApp/WorkbenchView.swift",
            "Sources/BreathApp/GitWorkbenchView.swift",
        ].map(sourceFile).joined(separator: "\n")
        let catalog = try sourceFile(
            "Sources/BreathApp/GitWorkbenchPersistence.swift"
        )
        let expression = try NSRegularExpression(
            pattern: #"commandID: "([^"]+)", keys: "([^"]+)""#
        )
        let range = NSRange(catalog.startIndex..., in: catalog)
        let bindings = expression.matches(in: catalog, range: range).compactMap {
            match -> (String, String)? in
            guard let commandRange = Range(match.range(at: 1), in: catalog),
                  let keysRange = Range(match.range(at: 2), in: catalog)
            else {
                return nil
            }
            return (
                String(catalog[commandRange]),
                String(catalog[keysRange])
            )
        }

        #expect(!bindings.isEmpty)
        for (commandID, keys) in bindings where !keys.isEmpty {
            #expect(
                sources.contains("\"\(commandID)\""),
                "Missing routed command surface for \(commandID)"
            )
        }
    }

    private func sourceFile(_ path: String) throws -> String {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        return try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
