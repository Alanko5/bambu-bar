import Foundation
import Security

/// Decides whether a printer's TLS certificate is genuine.
///
/// Bambu printers present a leaf named after their serial number, issued by a per-model "BBL Device CA"
/// that chains to Bambu's own roots ("BBL CA", "BBL CA2 RSA/ECC"). Those roots ship with the app; the
/// hostname is not checked because the certificate names the serial, not the IP address.
enum BambuTrust {
    static let anchors: [SecCertificate] = {
        guard let dir = Bundle.main.url(forResource: "Certificates", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "pem" }.flatMap { url -> [SecCertificate] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return certificates(fromPEM: text)
        }
    }()

    static func certificates(fromPEM pem: String) -> [SecCertificate] {
        pem.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst().compactMap { chunk in
            guard let body = chunk.components(separatedBy: "-----END CERTIFICATE-----").first else { return nil }
            let base64 = body.components(separatedBy: .whitespacesAndNewlines).joined()
            guard let der = Data(base64Encoded: base64) else { return nil }
            return SecCertificateCreateWithData(nil, der as CFData)
        }
    }

    enum Verdict: Equatable {
        /// Chains to a bundled Bambu root and is named after the expected printer.
        case trusted
        case rejected(String)

        var isRejected: Bool { if case .rejected = self { return true } else { return false } }
    }

    /// The most recent verdict, for `--probe` diagnostics.
    nonisolated(unsafe) static var lastVerdict: Verdict?

    static func evaluate(_ trust: SecTrust, serial: String) -> Verdict {
        let verdict = check(trust, serial: serial)
        lastVerdict = verdict
        return verdict
    }

    /// Both conditions matter: the chain proves it's a Bambu device, the name proves it's *this* printer
    /// (another Bambu printer on the network must not be able to collect the access code).
    private static func check(_ trust: SecTrust, serial: String) -> Verdict {
        SecTrustSetPolicies(trust, SecPolicyCreateBasicX509())
        SecTrustSetAnchorCertificates(trust, anchors as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            return .rejected((error as Error?)?.localizedDescription ?? "The certificate isn't from Bambu Lab.")
        }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            return .rejected("The printer sent no certificate.")
        }
        var name: CFString?
        SecCertificateCopyCommonName(leaf, &name)
        guard let name = name as String?, name.caseInsensitiveCompare(serial) == .orderedSame else {
            return .rejected("The certificate belongs to another device (\(name as String? ?? "unnamed")).")
        }
        return .trusted
    }
}
