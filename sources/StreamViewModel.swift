import SwiftUI
import AVFoundation

struct StreamConfig {
    var host: String
    var port: Int
    var portIsListener: Bool   // true: connect to port+1 (SHOUTcast v1 source port)
    var password: String
    var name: String
    var genre: String
    var url: String
    var isPublic: Bool
    var bitrate: Int
    var sampleRate: Double
    var stereo: Bool
    var sourcePort: Int { portIsListener ? port + 1 : port }
    var listenerPort: Int { portIsListener ? port : port - 1 }
}

final class StreamViewModel: ObservableObject {
    enum Phase: Equatable { case idle, connecting, live, error(String) }

    @Published var phase: Phase = .idle
    @Published var level: Float = 0
    @Published var bytesSent = 0
    @Published var elapsed: TimeInterval = 0
    @Published var titleStatus = ""

    var isBusy: Bool { phase == .connecting || phase == .live }

    private let encoder = MicMP3Encoder()
    private let client = ShoutcastClient()
    private var config: StreamConfig?
    private var timer: Timer?
    private var startedAt = Date()

    init() {
        let client = self.client
        encoder.onMP3 = { data in client.send(data) }
        encoder.onLevel = { [weak self] l in DispatchQueue.main.async { self?.level = l } }
        client.onEvent = { [weak self] ev in DispatchQueue.main.async { self?.handle(ev) } }
    }

    func start(_ c: StreamConfig) {
        guard !isBusy else { return }
        guard !c.host.isEmpty, (1...65535).contains(c.sourcePort) else {
            phase = .error("Enter a valid host and port"); return
        }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    self.phase = .error("Microphone access denied. Enable it in Settings > Privacy."); return
                }
                self.config = c
                self.phase = .connecting
                self.client.start(.init(host: c.host, sourcePort: c.sourcePort, password: c.password,
                                        name: c.name, genre: c.genre, url: c.url,
                                        isPublic: c.isPublic, bitrate: c.bitrate))
            }
        }
    }

    func stop() { teardown(); phase = .idle }

    private func handle(_ ev: ShoutcastClient.Event) {
        switch ev {
        case .connected:
            guard phase == .connecting, let c = config else { return }
            do {
                try encoder.start(.init(bitrate: c.bitrate, sampleRate: c.sampleRate, stereo: c.stereo))
                startedAt = Date()
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    self.elapsed = Date().timeIntervalSince(self.startedAt)
                    self.bytesSent = self.client.totalBytes
                }
                UIApplication.shared.isIdleTimerDisabled = true
                phase = .live
            } catch {
                teardown(); phase = .error(error.localizedDescription)
            }
        case .failed(let msg):
            guard isBusy else { return }
            teardown(); phase = .error(msg)
        }
    }

    private func teardown() {
        encoder.stop(); client.stop()
        timer?.invalidate(); timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        level = 0
    }

    func updateTitle(_ title: String, config c: StreamConfig) {
        titleStatus = "Updating…"
        ShoutcastClient.updateTitle(host: c.host, listenerPort: c.listenerPort,
                                    password: c.password, title: title) { ok in
            self.titleStatus = ok ? "Title updated" : "Title update failed"
        }
    }
}
