import AppKit
import BreathCore
import BreathSkills
import Foundation

@MainActor
final class SkillsViewModel: ObservableObject {
    @Published private(set) var snapshot: GlobalSkillsSnapshot = .empty
    @Published private(set) var updateCheck = SkillUpdateCheckResult(
        updates: [],
        failures: [],
        checkedAt: .distantPast,
        usedSessionCache: false
    )
    @Published var searchText = ""
    @Published var selectedAgent: AgentKind?
    @Published var selectedSource: SkillSourceKind?
    @Published var selectedStatus: SkillUpdateState?
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    let service: GlobalSkillsService
    private var watchTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    init(service: GlobalSkillsService) {
        self.service = service
    }

    deinit {
        watchTask?.cancel()
        updateTask?.cancel()
    }

    var filteredSkills: [GlobalSkill] {
        snapshot.skills.filter { skill in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || skill.name.localizedCaseInsensitiveContains(query)
                || skill.description.localizedCaseInsensitiveContains(query)
            let matchesAgent = selectedAgent.map { agent in
                skill.copies.contains { $0.agent == agent }
            } ?? true
            let matchesSource = selectedSource.map { source in
                skill.copies.contains { $0.source == source }
            } ?? true
            let matchesStatus = selectedStatus.map { status in
                if status == .locallyModified {
                    return skill.copies.contains(where: \.isLocallyModified)
                }
                return skill.copies.contains { $0.updateState == status }
            } ?? true
            return matchesSearch && matchesAgent && matchesSource && matchesStatus
        }
    }

    func activate() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            guard let self else { return }
            for await next in service.snapshots(debouncedBy: .milliseconds(250)) {
                guard !Task.isCancelled else { return }
                snapshot = next
            }
        }
        updateTask = Task { [weak self] in
            guard let self else { return }
            await service.beginUpdateCheckSession()
            let local = await service.scan()
            guard !Task.isCancelled else { return }
            snapshot = local
            await checkForUpdates(force: false)
        }
    }

    func deactivate() {
        watchTask?.cancel()
        watchTask = nil
        updateTask?.cancel()
        updateTask = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { [weak self] in
            guard let self else { return }
            snapshot = await service.scan()
            await checkForUpdates(force: true)
            isRefreshing = false
        }
    }

    func reconcileAfterApplicationActivation() {
        Task { [weak self] in
            guard let self else { return }
            snapshot = await service.scan()
        }
    }

    func accept(_ result: SkillOperationResult) {
        snapshot = result.snapshot
        refreshUpdatesAfterWrite()
    }

    func accept(_ result: SkillUninstallResult) {
        snapshot = result.snapshot
        refreshUpdatesAfterWrite()
    }

    func update(for skill: GlobalSkill) -> SkillAvailableUpdate? {
        updateCheck.updates.first { update in
            update.skillName == skill.name
                && update.targets.contains { target in
                    skill.copies.contains {
                        $0.agent == target.agent && $0.directory == target.directory
                    }
                }
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyDiagnostic(
        _ item: UnrecognizedSkillItem,
        localizedReason: String
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            "\(item.agentDisplayName) · \(item.path.lastPathComponent): \(localizedReason)",
            forType: .string
        )
    }

    private func checkForUpdates(force: Bool) async {
        updateCheck = await service.checkForUpdates(force: force)
        snapshot = await service.scan()
        if !updateCheck.failures.isEmpty,
           snapshot.skills.isEmpty
        {
            errorMessage = updateCheck.failures.map(\.message).joined(separator: "\n")
        }
    }

    private func refreshUpdatesAfterWrite() {
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            guard let self else { return }
            await checkForUpdates(force: true)
        }
    }
}
