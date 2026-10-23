import Foundation

/// Bambu Lab's texts for HMS codes and print errors in the app's language, P2S wording where it differs; English
/// for languages Bambu's HMS service doesn't offer and for codes a translation lacks.
/// Generated from ha-bambulab's catalogues (MIT) by scripts/make-hms.py.
final class HMSCatalog {
    static let shared = HMSCatalog()

    private typealias Tables = (hms: [String: String], errors: [String: String])
    private lazy var localized: Tables = Self.load(Self.language)
    private lazy var english: Tables = Self.language == "en" ? localized : Self.load("en")

    func hmsText(_ key: String) -> String? {
        let key = key.uppercased()
        return localized.hms[key] ?? english.hms[key]
    }

    func errorText(_ key: String) -> String? {
        let key = key.uppercased()
        return localized.errors[key] ?? english.errors[key]
    }

    static func wikiURL(for code: String) -> URL? {
        URL(string: "https://wiki.bambulab.com/en/hms/home")
    }

    /// The app's language if there's a catalogue for it. Traditional Chinese readers get the Simplified one,
    /// which Bambu Lab does publish, rather than English.
    private static var language: String {
        let lang = AppLanguage.current == "zh-Hant" ? "zh-Hans" : AppLanguage.current
        return Bundle.main.url(forResource: "hms_\(lang)", withExtension: "json.deflate") == nil ? "en" : lang
    }

    private static func load(_ language: String) -> Tables {
        guard let url = Bundle.main.url(forResource: "hms_\(language)", withExtension: "json.deflate"),
              let data = try? (Data(contentsOf: url) as NSData).decompressed(using: .zlib) as Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else { return ([:], [:]) }
        return (json["hms"] ?? [:], json["error"] ?? [:])
    }
}
