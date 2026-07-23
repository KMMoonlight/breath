import Foundation

public enum ManagedWorktreeState: String, Equatable, Codable, Sendable {
    case available
    case unavailable
}

public enum ManagedWorktreeStartBranchKind: String, Equatable, Sendable {
    case localBranch
    case remoteBranch
}

public struct ManagedWorktreeStartBranch: Equatable, Identifiable, Sendable {
    public var id: String { reference }

    public let reference: String
    public let name: String
    public let kind: ManagedWorktreeStartBranchKind
    public let isCurrent: Bool

    public init(
        reference: String,
        name: String,
        kind: ManagedWorktreeStartBranchKind,
        isCurrent: Bool
    ) {
        self.reference = reference
        self.name = name
        self.kind = kind
        self.isCurrent = isCurrent
    }
}

public struct ManagedWorktree: Equatable, Codable, Sendable {
    public let workspaceID: WorkspaceID
    public let workSessionID: WorkSessionID
    public let rootPath: String
    public let gitCommonDirectory: String
    public let baselineCommit: String
    public let workspaceRelativePath: String
    public let branchName: String
    public let createdBranch: Bool?
    public var state: ManagedWorktreeState

    public init(
        workspaceID: WorkspaceID,
        workSessionID: WorkSessionID,
        rootPath: String,
        gitCommonDirectory: String,
        baselineCommit: String,
        workspaceRelativePath: String,
        branchName: String,
        createdBranch: Bool? = nil,
        state: ManagedWorktreeState = .available
    ) {
        self.workspaceID = workspaceID
        self.workSessionID = workSessionID
        self.rootPath = rootPath
        self.gitCommonDirectory = gitCommonDirectory
        self.baselineCommit = baselineCommit
        self.workspaceRelativePath = workspaceRelativePath
        self.branchName = branchName
        self.createdBranch = createdBranch
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID
        case workSessionID
        case rootPath
        case gitCommonDirectory
        case baselineCommit
        case workspaceRelativePath
        case branchName
        case createdBranch = "createdTaskBranch"
        case state
    }

    public var workingDirectory: String {
        guard !workspaceRelativePath.isEmpty else { return rootPath }
        return URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(workspaceRelativePath, isDirectory: true)
            .standardizedFileURL
            .path
    }

    public static func sessionBranchName(
        for workSessionID: WorkSessionID
    ) -> String {
        "breath/\(workSessionID.rawValue.uuidString.lowercased())"
    }
}

public protocol ManagedWorktreeManaging: Sendable {
    func startBranches(
        for workspace: Workspace
    ) async throws -> [ManagedWorktreeStartBranch]

    func create(
        workspace: Workspace,
        workSessionID: WorkSessionID,
        branchName: String,
        startBranch: ManagedWorktreeStartBranch?
    ) async throws -> ManagedWorktree

    func isAvailable(_ worktree: ManagedWorktree) async -> Bool
    func validateRemoval(_ worktree: ManagedWorktree) async throws
    func remove(_ worktree: ManagedWorktree) async throws
    func rollbackCreation(_ worktree: ManagedWorktree) async throws
}

public extension ManagedWorktreeManaging {
    func create(
        workspace: Workspace,
        workSessionID: WorkSessionID,
        branchName: String
    ) async throws -> ManagedWorktree {
        try await create(
            workspace: workspace,
            workSessionID: workSessionID,
            branchName: branchName,
            startBranch: nil
        )
    }

    func rollbackCreation(_ worktree: ManagedWorktree) async throws {
        try await remove(worktree)
    }
}
