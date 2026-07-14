import Foundation
import Sparkle

public struct UpdateConfiguration: Equatable, Sendable {
    public let feedURL: URL?
    public let publicEDKey: String?

    public init(infoDictionary: [String: Any]) {
        if let value = infoDictionary["SUFeedURL"] as? String,
           let url = URL(string: value),
           url.scheme?.lowercased() == "https"
        {
            feedURL = url
        } else {
            feedURL = nil
        }

        if let value = infoDictionary["SUPublicEDKey"] as? String,
           let data = Data(base64Encoded: value),
           data.count == 32
        {
            publicEDKey = value
        } else {
            publicEDKey = nil
        }
    }

    public var isReady: Bool {
        feedURL != nil && publicEDKey != nil
    }
}

@MainActor
public final class BreathUpdateController {
    public let configuration: UpdateConfiguration
    private let controller: SPUStandardUpdaterController

    public init(bundle: Bundle = .main) {
        configuration = UpdateConfiguration(
            infoDictionary: bundle.infoDictionary ?? [:]
        )
        controller = SPUStandardUpdaterController(
            startingUpdater: configuration.isReady,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    public var canCheckForUpdates: Bool {
        configuration.isReady && controller.updater.canCheckForUpdates
    }

    public func checkForUpdates() {
        guard configuration.isReady else { return }
        controller.checkForUpdates(nil)
    }
}
