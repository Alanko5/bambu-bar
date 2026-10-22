import Foundation

/// English texts for HMS codes and print errors, P2S wording where it differs.
/// Generated from ha-bambulab's catalogue (MIT) by scripts/make-hms.py.
final class HMSCatalog {
    static let shared = HMSCatalog()

    private var hms: [String: String] = [:]
    private var errors: [String: String] = [:]
    private var loaded = false

    func hmsText(_ key: String) -> String? {
        load()
        return hms[key.uppercased()]
    }

    func errorText(_ key: String) -> String? {
        load()
        return errors[key.uppercased()]
    }

    static func wikiURL(for code: String) -> URL? {
        URL(string: "https://wiki.bambulab.com/en/hms/home")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let url = Bundle.main.url(forResource: "hms_en", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else { return }
        hms = json["hms"] ?? [:]
        errors = json["error"] ?? [:]
    }
}
