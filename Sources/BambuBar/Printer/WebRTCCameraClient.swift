import AppKit
import CoreGraphics
import ImageIO
import WebKit

/// The Creality K1 camera: H.264 over WebRTC, signalled with one POST of a base64 JSON offer to
/// `http://<host>:8000/call/webrtc_local`, answered the same way.
///
/// WebKit does the WebRTC (ICE, DTLS, SRTP, decoding) in a web view that's never on screen; each decoded frame is
/// drawn to a canvas and handed over as a JPEG, so the app shows it like the P1/A1 stream. Two things make it work:
/// WebKit hides the Mac's address behind an mDNS name (`<uuid>.local`) the printer can't resolve, so the offer
/// carries the real address on the printer's network instead; and the page is exempt from the throttling WebKit
/// applies to views that aren't visible.
final class WebRTCCameraClient: NSObject, CameraClient, WKScriptMessageHandler {
    var onEvent: ((CameraEvent) -> Void)?
    var log: ((String) -> Void)?

    private let config: CameraConfig
    private var web: WKWebView?
    /// WebKit renders video only for a view in a window; this one is never shown.
    private var window: NSWindow?
    private var frames = 0
    private var lastFrame = Date()
    private var watchdog: Timer?
    private var finished = false

    init(_ config: CameraConfig) {
        self.config = config
    }

    func start() {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.open() } }
    }

    func stop() {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.finish(nil) } }
    }

    var signalURL: URL? { URL(string: "http://\(config.host):\(CameraTransport.webrtc.port)/call/webrtc_local") }

    @MainActor
    private func open() {
        guard !finished, let signal = signalURL else { return }
        let local = Self.localAddress(toward: config.host)
        log?("signalling at \(signal.absoluteString), offering \(local ?? "the mDNS address")")
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Off screen, WebKit would slow the page to about a frame a second.
        configuration.preferences.inactiveSchedulingPolicy = .none
        configuration.userContentController.add(WeakHandler(self), name: "camera")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 16, height: 9), configuration: configuration)
        let window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        self.web = web
        self.window = window
        web.loadHTMLString(Self.page(signal: signal, localAddress: local),
                           baseURL: URL(string: "http://\(config.host):\(CameraTransport.webrtc.port)/"))
        lastFrame = Date()
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(self.lastFrame) > 15 else { return }
                self.finish(self.frames == 0 ? .unreachable("The camera didn't start.") : .timedOut)
            }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { self.received(message.body) }
    }

    @MainActor
    private func received(_ body: Any) {
        guard !finished, let text = body as? String else { return }
        if text.hasPrefix("data:image/jpeg;base64,") {
            guard let data = Data(base64Encoded: String(text.dropFirst(23))),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
            lastFrame = Date()
            frames += 1
            if frames == 1 {
                log?("first frame \(image.width)×\(image.height)")
                onEvent?(.started("H.264 · \(image.width)×\(image.height)", size: CGSize(width: image.width, height: image.height)))
            }
            onEvent?(.image(image))
        } else if text.hasPrefix("failed ") {
            finish(.unreachable(String(text.dropFirst(7))))
        } else if text == "closed" {
            finish(.closed)
        } else {
            log?(text)
        }
    }

    @MainActor
    private func finish(_ failure: CameraFailure?) {
        guard !finished else { return }
        finished = true
        watchdog?.invalidate()
        watchdog = nil
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "camera")
        // Leaving the page closes the peer connection, so the printer stops sending.
        web?.loadHTMLString("", baseURL: nil)
        web = nil
        window?.contentView = nil
        window = nil
        if let failure {
            log?("closed: \(failure)")
            onEvent?(.failed(failure))
        }
    }

    /// The Mac's IPv4 address on the route to `host`: a UDP socket "connected" to it (nothing is sent) has it as
    /// its local address.
    static func localAddress(toward host: String) -> String? {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_DGRAM, ai_protocol: 0,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "\(CameraTransport.webrtc.port)", &hints, &info) == 0, let info else { return nil }
        defer { freeaddrinfo(info) }
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else { return nil }
        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) == 0 }
        }
        guard ok else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &local.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: buffer)
    }

    private static func page(signal: URL, localAddress: String?) -> String {
        func js(_ text: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        }
        return """
        <!doctype html>
        <html><body>
        <video id="v" autoplay muted playsinline style="width: 16px; height: 9px"></video>
        <script>
        const post = text => window.webkit.messageHandlers.camera.postMessage(text);
        const video = document.getElementById("v");
        // Encoding a JPEG takes longer than a frame lasts, so two canvases take turns.
        const canvases = [document.createElement("canvas"), document.createElement("canvas")];
        let next = 0, inFlight = 0, sent = 0;

        // Each decoded frame, as a JPEG, in order; frames that arrive while both canvases are busy are skipped.
        function grab() {
            video.requestVideoFrameCallback(grab);
            if (inFlight >= canvases.length || !video.videoWidth) return;
            const canvas = canvases[next];
            next = (next + 1) % canvases.length;
            inFlight++;
            const order = ++sent;
            canvas.width = video.videoWidth;
            canvas.height = video.videoHeight;
            canvas.getContext("2d").drawImage(video, 0, 0);
            canvas.toBlob(blob => {
                const reader = new FileReader();
                reader.onload = () => { inFlight--; if (order > delivered) { delivered = order; post(reader.result); } };
                reader.readAsDataURL(blob);
            }, "image/jpeg", 0.8);
        }
        let delivered = 0;

        (async () => {
            try {
                const pc = new RTCPeerConnection({ iceServers: [] });
                pc.addTransceiver("video", { direction: "recvonly" });
                pc.ontrack = e => { video.srcObject = e.streams[0] || new MediaStream([e.track]); };
                pc.onconnectionstatechange = () => {
                    post("connection " + pc.connectionState);
                    if (pc.connectionState === "failed") post("failed The camera connection failed.");
                    if (pc.connectionState === "disconnected" || pc.connectionState === "closed") post("closed");
                };
                await pc.setLocalDescription(await pc.createOffer());
                await new Promise(done => {
                    if (pc.iceGatheringState === "complete") return done();
                    pc.onicegatheringstatechange = () => pc.iceGatheringState === "complete" && done();
                    setTimeout(done, 1500);
                });
                let sdp = pc.localDescription.sdp;
                const local = \(js(localAddress ?? ""));
                if (local) sdp = sdp.replace(/[0-9a-fA-F-]{36}\\.local/g, local);
                const response = await fetch(\(js(signal.absoluteString)), {
                    method: "POST", headers: { "Content-Type": "text/plain" },
                    body: btoa(JSON.stringify({ type: "offer", sdp }))
                });
                if (!response.ok) throw new Error("the printer answered HTTP " + response.status);
                await pc.setRemoteDescription(JSON.parse(atob((await response.text()).trim())));
                post("answer set");
                video.requestVideoFrameCallback(grab);
            } catch (error) {
                post("failed The camera didn't answer: " + error.message);
            }
        })();
        </script></body></html>
        """
    }
}

/// `WKUserContentController` holds its handlers strongly; this keeps it from holding the client.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
