import BreathCore
import Foundation
import Testing
@testable import BreathApp

@Suite("Application localization")
struct ApplicationLocalizationTests {
    @Test("system language resolves Chinese and otherwise falls back to English")
    func systemLanguageResolution() {
        #expect(
            ApplicationLocalizer(
                language: .system,
                preferredLanguages: ["zh-Hans-CN"]
            ).resolvedLanguage == .chinese
        )
        #expect(
            ApplicationLocalizer(
                language: .system,
                preferredLanguages: ["en-US"]
            ).resolvedLanguage == .english
        )
        #expect(
            ApplicationLocalizer(
                language: .system,
                preferredLanguages: ["fr-FR"]
            ).resolvedLanguage == .english
        )
    }

    @Test("localized resources provide Chinese and English interface text")
    func localizedResources() {
        let chinese = ApplicationLocalizer(language: .chinese)
        let english = ApplicationLocalizer(language: .english)

        #expect(chinese.string("工作区") == "工作区")
        #expect(english.string("工作区") == "Workspace")
        #expect(english.string("打开工作区") == "Open Workspace")
        #expect(english.format("终端 %d", 2) == "Terminal 2")
        #expect(english.format("使用 %@ 打开工作区", "Zed") == "Open Workspace in Zed")
        #expect(english.string("选择编辑器") == "Choose Editor")
        #expect(english.string("Git 工作台") == "Git Workbench")
        #expect(english.string("Git 目录") == "Git Directory")
        #expect(english.string("请选择") == "Choose…")
        #expect(english.string("提交信息") == "Commit Message")
        #expect(english.string("解决冲突…") == "Resolve Conflicts…")
        #expect(english.string("正在下载…") == "Downloading…")
        #expect(english.string("正在安装…") == "Installing…")
        #expect(english.format("安装 %@", "Kami") == "Install Kami")
        #expect(english.string("安装状态") == "Installation Status")
        #expect(english.string("额度") == "Quota")
        #expect(english.string("每月") == "Monthly")
        #expect(english.string("额度查询超时。") == "Quota query timed out.")
        #expect(chinese.string("此 Skill 已安装") == "此 Skill 已安装")
        #expect(english.format("作者：%@", "Example") == "Author: Example")
        #expect(
            localizedSkillMessage(
                "SKILL.md is missing.",
                localizer: chinese
            ) == "缺少 SKILL.md。"
        )
        #expect(
            localizedSkillMessage(
                "Claude Code is not installed.",
                localizer: chinese
            ) == "未安装 Claude Code。"
        )
        #expect(
            localizedSkillMessage(
                "Codex 0.1 is older than the supported 1.0.",
                localizer: chinese
            ) == "Codex 0.1 低于受支持的最低版本 1.0。"
        )
    }

    @Test("Git workbench localization keys exist in both languages with matching placeholders")
    func gitWorkbenchLocalizationCoverage() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let resourceRoot = root.appendingPathComponent(
            "Sources/BreathApp/Resources",
            isDirectory: true
        )
        let chinese = try localizationEntries(
            at: resourceRoot.appendingPathComponent(
                "zh-Hans.lproj/Localizable.strings"
            )
        )
        let english = try localizationEntries(
            at: resourceRoot.appendingPathComponent(
                "en.lproj/Localizable.strings"
            )
        )
        let sourceFiles = [
            "Sources/BreathApp/GitWorkbenchView.swift",
            "Sources/BreathApp/BreathSettingsView.swift",
            "Sources/BreathApp/BreathApp.swift",
            "Sources/BreathApp/WorkbenchView.swift",
            "Sources/BreathApp/SkillsView.swift",
            "Sources/BreathApp/AgentQuotaView.swift",
        ]
        let referencedKeys = try sourceFiles.reduce(into: Set<String>()) {
            result,
            path in
            let source = try String(
                contentsOf: root.appendingPathComponent(path),
                encoding: .utf8
            )
            result.formUnion(localizationKeys(in: source))
        }

        #expect(Set(chinese.keys) == Set(english.keys))
        #expect(referencedKeys.subtracting(english.keys).isEmpty)
        for key in referencedKeys {
            #expect(
                placeholderSignature(chinese[key, default: ""])
                    == placeholderSignature(key)
            )
            #expect(
                placeholderSignature(english[key, default: ""])
                    == placeholderSignature(key)
            )
        }
    }

    @Test("language setting is wired into settings and the app window")
    func languageSettingWiring() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let settingsSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/BreathSettingsView.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/BreathApp.swift"),
            encoding: .utf8
        )
        let workbenchSource = try String(
            contentsOf: root.appendingPathComponent("Sources/BreathApp/WorkbenchView.swift"),
            encoding: .utf8
        )

        #expect(settingsSource.contains("selection: applicationLanguage"))
        #expect(settingsSource.contains("ApplicationLanguage.system"))
        #expect(settingsSource.contains("ApplicationLanguage.chinese"))
        #expect(settingsSource.contains("ApplicationLanguage.english"))
        #expect(
            appSource.components(
                separatedBy: ".applicationLanguage(model.settings.application.language)"
            ).count == 2
        )
        #expect(workbenchSource.contains("Text(localizer.string(\"工作区\"))"))
    }

    private func localizationEntries(at url: URL) throws -> [String: String] {
        let source = try String(contentsOf: url, encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"^"([^"]+)"\s*=\s*"([^"]*)";$"#,
            options: [.anchorsMatchLines]
        )
        var entries: [String: String] = [:]
        let range = NSRange(source.startIndex..., in: source)
        for match in expression.matches(in: source, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: source),
                  let valueRange = Range(match.range(at: 2), in: source)
            else {
                continue
            }
            entries[String(source[keyRange])] = String(source[valueRange])
        }
        return entries
    }

    private func localizationKeys(in source: String) -> Set<String> {
        let expression = try? NSRegularExpression(
            pattern: #"localizer\.(?:string|format)\(\s*"([^"]+)""#
        )
        guard let expression else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return Set(expression.matches(in: source, range: range).compactMap {
            guard let keyRange = Range($0.range(at: 1), in: source) else {
                return nil
            }
            return String(source[keyRange])
        })
    }

    private func placeholderSignature(_ value: String) -> [String] {
        let expression = try? NSRegularExpression(pattern: #"%[@d]"#)
        guard let expression else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }
}
