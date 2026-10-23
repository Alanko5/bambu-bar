import Foundation
import Network

/// Finds out which printer answers at an address, for a printer added by its IP address alone: its certificate
/// chains to Bambu Lab and is named after its serial. Only the TLS handshake happens; the access code isn't sent.
enum PrinterIdentity {
    enum Failure: Error, Equatable {
        case notBambu(String)
        case unreachable(String)
        case localNetworkDenied
        case timedOut

        var message: String {
            switch self {
            case .notBambu(let reason): return "That address didn't answer as a Bambu Lab printer: \(reason)"
            case .unreachable(let reason): return "\(reason) Check the IP address on the printer's screen (Settings → Network)."
            case .localNetworkDenied: return LocalNetwork.advice
            case .timedOut: return "Nothing answered at that address. Check the IP address on the printer's screen (Settings → Network)."
            }
        }
    }

    static func serial(host: String, port: UInt16, insecure: Bool, timeout: TimeInterval = 10) async -> Result<String, Failure> {
        await withCheckedContinuation { continuation in
            Lookup(insecure: insecure) { continuation.resume(returning: $0) }.start(host: host, port: port, timeout: timeout)
        }
    }

    /// One handshake. Everything after `start` happens on `queue`.
    private final class Lookup: @unchecked Sendable {
        private let queue = DispatchQueue(label: "dev.rolottr.BambuBar.identify")
        private let insecure: Bool
        private let completion: (Result<String, Failure>) -> Void
        private var connection: NWConnection?
        private var identity: BambuTrust.Identity?
        private var done = false

        init(insecure: Bool, completion: @escaping (Result<String, Failure>) -> Void) {
            self.insecure = insecure
            self.completion = completion
        }

        func start(host: String, port: UInt16, timeout: TimeInterval) {
            let tls = MQTTClient.tlsOptions(queue: queue) { [self] trust in
                // The emulators' certificates come from their own CA; their names are still the serials.
                identity = insecure ? .genuine(name: BambuTrust.commonName(trust)) : BambuTrust.identify(trust)
                if case .genuine = identity { return true }
                return false
            }
            let tcp = NWProtocolTCP.Options()
            tcp.connectionTimeout = Int(timeout)
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!,
                                          using: NWParameters(tls: tls, tcp: tcp))
            self.connection = connection
            // The handler keeps the lookup alive until it finishes.
            connection.stateUpdateHandler = { [self] state in handle(state) }
            queue.asyncAfter(deadline: .now() + timeout + 4) { [self] in finish(.failure(.timedOut)) }
            connection.start(queue: queue)
        }

        private func handle(_ state: NWConnection.State) {
            switch state {
            case .ready:
                if case .genuine(let name?) = identity, !name.isEmpty {
                    finish(.success(name.uppercased()))
                } else {
                    finish(.failure(.notBambu("its certificate doesn't name it.")))
                }
            case .waiting(let error), .failed(let error):
                if connection?.currentPath?.unsatisfiedReason == .localNetworkDenied {
                    finish(.failure(.localNetworkDenied))
                } else if case .rejected(let reason) = identity {
                    finish(.failure(.notBambu(reason)))
                } else {
                    finish(.failure(.unreachable(MQTTClient.describe(error))))
                }
            default:
                break
            }
        }

        private func finish(_ result: Result<String, Failure>) {
            guard !done else { return }
            done = true
            connection?.stateUpdateHandler = nil
            connection?.cancel()
            connection = nil
            completion(result)
        }
    }
}
