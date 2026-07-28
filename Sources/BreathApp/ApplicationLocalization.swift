import BreathCore
import Foundation
import SwiftUI

struct ApplicationLocalizer {
    let resolvedLanguage: ApplicationLanguage

    init(
        language: ApplicationLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        switch language {
        case .system:
            let preferredLanguage = preferredLanguages.first?.lowercased() ?? ""
            resolvedLanguage = preferredLanguage.hasPrefix("zh") ? .chinese : .english
        case .chinese, .english:
            resolvedLanguage = language
        }
    }

    var locale: Locale {
        Locale(identifier: localizationIdentifier)
    }

    func string(_ key: String) -> String {
        guard let path = BreathResources.bundle.path(
            forResource: localizationIdentifier,
            ofType: "lproj"
        ), let bundle = Bundle(path: path)
        else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: locale,
            arguments: arguments
        )
    }

    private var localizationIdentifier: String {
        switch resolvedLanguage {
        case .chinese: "zh-hans"
        case .english, .system: "en"
        }
    }
}

private struct ApplicationLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue = ApplicationLanguage.system
}

extension EnvironmentValues {
    var applicationLanguage: ApplicationLanguage {
        get { self[ApplicationLanguageEnvironmentKey.self] }
        set { self[ApplicationLanguageEnvironmentKey.self] = newValue }
    }
}

extension View {
    func applicationLanguage(_ language: ApplicationLanguage) -> some View {
        let localizer = ApplicationLocalizer(language: language)
        return environment(\.applicationLanguage, language)
            .environment(\.locale, localizer.locale)
    }
}
