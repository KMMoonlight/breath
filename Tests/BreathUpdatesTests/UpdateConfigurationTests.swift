import Foundation
import Testing
@testable import BreathUpdates

@Suite("Sparkle update configuration")
struct UpdateConfigurationTests {
    @Test("accepts an HTTPS feed and a 32-byte Ed25519 public key")
    func acceptsSecureConfiguration() {
        let key = Data(repeating: 0x2A, count: 32).base64EncodedString()

        let configuration = UpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://breath.example/appcast.xml",
            "SUPublicEDKey": key,
        ])

        #expect(configuration.feedURL == URL(string: "https://breath.example/appcast.xml"))
        #expect(configuration.publicEDKey == key)
        #expect(configuration.isReady)
    }

    @Test("rejects missing, insecure, and malformed update metadata")
    func rejectsUnsafeConfiguration() {
        let validKey = Data(repeating: 0x2A, count: 32).base64EncodedString()
        let cases: [[String: Any]] = [
            [:],
            ["SUFeedURL": "http://breath.example/appcast.xml", "SUPublicEDKey": validKey],
            ["SUFeedURL": "https://breath.example/appcast.xml", "SUPublicEDKey": "not-a-key"],
        ]

        for infoDictionary in cases {
            #expect(!UpdateConfiguration(infoDictionary: infoDictionary).isReady)
        }
    }
}
