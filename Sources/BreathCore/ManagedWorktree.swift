import Foundation

public enum ManagedWorktreeState: String, Equatable, Codable, Sendable {
    case available
    case unavailable
}

public struct ManagedWorktree: Equatable, Codable, Sendable {
    public let workspaceID: WorkspaceID
    public let workSessionID: WorkSessionID
    public let rootPath: String
    public let gitCommonDirectory: String
    public let baselineCommit: String
    public let workspaceRelativePath: String
    public let branchName: String
    public var state: ManagedWorktreeState

    public init(
        workspaceID: WorkspaceID,
        workSessionID: WorkSessionID,
        rootPath: String,
        gitCommonDirectory: String,
        baselineCommit: String,
        workspaceRelativePath: String,
        branchName: String,
        state: ManagedWorktreeState = .available
    ) {
        self.workspaceID = workspaceID
        self.workSessionID = workSessionID
        self.rootPath = rootPath
        self.gitCommonDirectory = gitCommonDirectory
        self.baselineCommit = baselineCommit
        self.workspaceRelativePath = workspaceRelativePath
        self.branchName = branchName
        self.state = state
    }

    public var workingDirectory: String {
        guard !workspaceRelativePath.isEmpty else { return rootPath }
        return URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(workspaceRelativePath, isDirectory: true)
            .standardizedFileURL
            .path
    }
}

public protocol ManagedWorktreeManaging: Sendable {
    func create(
        workspace: Workspace,
        workSessionID: WorkSessionID,
        branchName: String
    ) async throws -> ManagedWorktree

    func isAvailable(_ worktree: ManagedWorktree) async -> Bool
    func validateRemoval(_ worktree: ManagedWorktree) async throws
    func remove(_ worktree: ManagedWorktree) async throws
}
