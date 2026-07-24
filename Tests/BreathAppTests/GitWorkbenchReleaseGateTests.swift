import Foundation
import Testing

@Suite("Git workbench release gate")
struct GitWorkbenchReleaseGateTests {
    @Test("all 208 stories are covered exactly once by the acceptance matrix")
    func acceptanceMatrixCoversEveryStory() throws {
        let matrix = try sourceFile(
            ".scratch/git-workbench/release-acceptance.md"
        )
        let expression = try NSRegularExpression(
            pattern: #"Stories (\d+)(?:–(\d+))?"#
        )
        let range = NSRange(matrix.startIndex..., in: matrix)
        var covered: [Int] = []

        for match in expression.matches(in: matrix, range: range) {
            guard let firstRange = Range(match.range(at: 1), in: matrix),
                  let first = Int(matrix[firstRange])
            else {
                continue
            }
            let last: Int
            if let lastRange = Range(match.range(at: 2), in: matrix),
               let parsed = Int(matrix[lastRange])
            {
                last = parsed
            } else {
                last = first
            }
            covered.append(contentsOf: first...last)
        }

        #expect(covered == Array(1...208))
    }

    @Test("the public release remains gated until manual acceptance is recorded")
    func publicReleaseRemainsGated() throws {
        let gate = try sourceFile(
            "Sources/BreathApp/GitWorkbenchReleaseGate.swift"
        )
        let shell = try sourceFile("Sources/BreathApp/WorkbenchView.swift")
        let app = try sourceFile("Sources/BreathApp/BreathApp.swift")

        #expect(gate.contains("#if DEBUG"))
        #expect(gate.contains("BREATH_ENABLE_GIT_WORKBENCH"))
        #expect(shell.contains("GitWorkbenchReleaseGate.isEnabled"))
        #expect(app.contains("GitWorkbenchReleaseGate.isEnabled"))
    }

    @Test("scope exclusions and force-push safety remain enforced")
    func scopeAndForceSafety() throws {
        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let gitSources = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Sources/BreathApp"),
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.lastPathComponent.hasPrefix("Git")
                && $0.pathExtension == "swift"
        }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")

        #expect(!gitSources.contains("import BreathAgents"))
        #expect(!gitSources.contains("git worktree"))
        #expect(!gitSources.contains("worktree add"))
        #expect(!gitSources.contains("worktree remove"))
        #expect(
            gitSources.components(separatedBy: "\"--force\"").count - 1 == 3
        )
        #expect(
            gitSources.contains(
                "guard !arguments.contains(\"--force\") else"
            )
        )
        #expect(gitSources.contains("--force-with-lease"))
    }

    @Test("confirmed edge workflows have complete command and UI surfaces")
    func confirmedEdgeWorkflowSurfacesExist() throws {
        let service = try sourceFile(
            "Sources/BreathApp/GitRepositoryMutations.swift"
        )
        let snapshots = try sourceFile(
            "Sources/BreathApp/GitSafetySnapshotStore.swift"
        )
        let model = try sourceFile(
            "Sources/BreathApp/GitWorkbenchViewModel.swift"
        )
        let view = try sourceFile(
            "Sources/BreathApp/GitWorkbenchView.swift"
        )

        #expect(service.contains("func deleteRemoteBranch("))
        #expect(service.contains("\"--delete\""))
        #expect(service.contains("if sign {"))
        #expect(service.contains("\"-s\""))
        #expect(service.contains("supportsInitialBranchOption"))
        #expect(service.contains("supportsSwitchAndRestore"))
        #expect(service.contains("[\"checkout\", \"--\"]"))
        #expect(model.contains("func synchronizeReset("))
        #expect(model.contains("func synchronizePush("))
        #expect(snapshots.contains("func comparisonDiff("))
        #expect(view.contains("恢复文件"))
        #expect(view.contains("重新应用自动合并结果"))
        #expect(view.contains("可编辑 Staged 结果"))
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
