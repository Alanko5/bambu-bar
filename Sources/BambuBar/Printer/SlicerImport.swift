import Foundation

/// A printer some slicer already knows the access code for.
struct SlicerPrinter: Equatable, Identifiable {
    var id: String { serial }
    var serial: String
    /// Best first. Bambu Studio keeps the code it got from the cloud (`access_code`) and the one typed in
    /// for LAN mode (`user_access_code`); either may be stale, so both are kept to try in turn.
    var accessCodes: [String]
    var host: String?
    var name: String?
    /// "Bambu Studio", "OrcaSlicer"…
    var source: String
}

/// Reads access codes out of Bambu Studio's and OrcaSlicer's settings, so setup needs no typing.
///
/// Both slicers save `<Application Support>/<App>/<App>.conf` as JSON (on Windows with an MD5 line after it)
/// with one object per section: `access_code` and `user_access_code` map serial → code, `ip_address` and
/// `user_access_dev_ip` map serial → IP (BambuStudio `DevManager.cpp`, `AppConfig.cpp`).
enum SlicerImport {
    static let knownApps = [("BambuStudio", "Bambu Studio"), ("BambuStudioBeta", "Bambu Studio Beta"),
                            ("OrcaSlicer", "OrcaSlicer"), ("OrcaSlicerNightly", "OrcaSlicer Nightly")]

    /// This Mac's `~/Library/Application Support`.
    static var localSupport: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// Where the file panel should open: Bambu Studio's folder when there is one, else Application Support.
    static var suggestedFolder: URL? {
        guard let support = localSupport else { return nil }
        for (folder, _) in knownApps {
            let dir = support.appendingPathComponent(folder)
            if FileManager.default.fileExists(atPath: dir.path) { return dir }
        }
        return support
    }

    /// Every printer with a stored access code in this Mac's slicers.
    static func scan() -> [SlicerPrinter] {
        guard let support = localSupport else { return [] }
        return read(supportFolder: support, suffix: nil)
    }

    private static func read(supportFolder: URL, suffix: String?) -> [SlicerPrinter] {
        var found: [SlicerPrinter] = []
        for (folder, title) in knownApps {
            let url = supportFolder.appendingPathComponent(folder).appendingPathComponent("\(folder).conf")
            let source = suffix.map { "\(title) on \($0)" } ?? title
            for printer in read(url, source: source) where !found.contains(where: { $0.serial == printer.serial }) {
                found.append(printer)
            }
        }
        return found
    }

    /// Reads a settings file, or a folder holding one (Bambu Studio's own folder, Application Support, a home
    /// folder or a whole disk), as picked or dropped by the person.
    static func read(picked url: URL) -> [SlicerPrinter] {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return [] }
        guard isFolder.boolValue else {
            let source = url.lastPathComponent.lowercased().hasPrefix("orca") ? "OrcaSlicer" : "Bambu Studio"
            return read(url, source: "\(source) settings file")
        }
        let candidates = [url, url.appendingPathComponent("Library/Application Support")]
            + knownApps.map { url.appendingPathComponent($0.0) }
        for candidate in candidates {
            // Bambu Studio's own folder: the .conf sits right inside it.
            for (folder, title) in knownApps {
                let conf = candidate.appendingPathComponent("\(folder).conf")
                let printers = read(conf, source: title)
                if !printers.isEmpty { return printers }
            }
            let printers = read(supportFolder: candidate, suffix: nil)
            if !printers.isEmpty { return printers }
        }
        // A whole disk.
        let users = url.appendingPathComponent("Users")
        for user in (try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            let printers = read(supportFolder: user.appendingPathComponent("Library/Application Support"), suffix: nil)
            if !printers.isEmpty { return printers }
        }
        return []
    }

    /// Parses one config file.
    static func read(_ url: URL, source: String) -> [SlicerPrinter] {
        guard let data = try? Data(contentsOf: url), var text = String(data: data, encoding: .utf8) else { return [] }
        // Drop anything after the JSON object (the "# MD5 checksum …" line some builds append).
        if let end = text.lastIndex(of: "}") { text = String(text[...end]) }
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return [] }

        func section(_ name: String) -> [String: String] {
            guard let dict = json[name] as? [String: Any] else { return [:] }
            return dict.compactMapValues { value -> String? in
                let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return s.isEmpty ? nil : s
            }
        }
        let cloud = section("access_code"), typed = section("user_access_code")
        let ips = section("ip_address"), typedIPs = section("user_access_dev_ip")
        let serials = Set(cloud.keys).union(typed.keys)
        return serials.sorted().compactMap { serial in
            var codes: [String] = []
            for code in [cloud[serial], typed[serial]].compactMap({ $0 }) where !codes.contains(code) { codes.append(code) }
            guard !codes.isEmpty else { return nil }
            return SlicerPrinter(serial: serial, accessCodes: codes, host: typedIPs[serial] ?? ips[serial], name: nil, source: source)
        }
    }
}
