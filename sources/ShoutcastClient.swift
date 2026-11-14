import Foundation
import Network

/// SHOUTcast v1 source client.
/// Protocol: connect to (listener port + 1), send "<password>\r\n", expect "OK2",
/// send icy-* headers + blank line, then stream raw MP3 bytes.
final class ShoutcastClient {
    struct Config {
        var host: String
        var sourcePort: Int
        var password: String
        var name: String
        var genre: String
        var url: String
        var isPublic: Bool
        var bitrate: Int
    }
    enum Event { case connected, failed(String) }

    var onEvent: ((Event) -> Void)?

    private let queue = DispatchQueue(label: "shoutcast.net")
    private var conn: NWConnection?
    private var ready = false
    private var pending = 0
    private let lock = NSLock()
    private var _bytes = 0
    var totalBytes: Int { lock.lock(); defer { lock.unlock() }; return _bytes }

    func start(_ c: Config) {
        lock.lock(); _bytes = 0; lock.unlock()
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: c.sourcePort)) else {
            onEvent?(.failed("Invalid port")); return
        }
        let conn = NWConnection(host: NWEndpoint.Host(c.host), port: port, using: .tcp)
        self.conn = conn
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self = self, let conn = conn, conn === self.conn else { return }
            switch state {
            case .ready: self.handshake(conn, c)
            case .waiting(let e), .failed(let e): self.fail(conn, "Connection error: \(e.localizedDescription)")
            default: break
            }
        }
        conn.start(queue: queue)
    }

    private func handshake(_ conn: NWConnection, _ c: Config) {
        conn.send(content: "\(c.password)\r\n".data(using: .utf8), completion: .contentProcessed { _ in })
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, _, error in
            guard let self = self, conn === self.conn else { return }
            let reply = String(data: data ?? Data(), encoding: .utf8) ?? ""
            guard error == nil, reply.hasPrefix("OK") else {
                let r = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                self.fail(conn, r.isEmpty ? "No response from server" : "Server said: \(r)")
                return
            }
            let headers = [
                "icy-name:\(c.name)", "icy-genre:\(c.genre)", "icy-url:\(c.url)",
                "icy-pub:\(c.isPublic ? 1 : 0)", "icy-br:\(c.bitrate)",
                "content-type:audio/mpeg",
            ].joined(separator: "\r\n") + "\r\n\r\n"
            conn.send(content: headers.data(using: .utf8), completion: .contentProcessed { _ in })
            self.ready = true
            self.onEvent?(.connected)
            self.watch(conn)
        }
    }

    /// Detect the server closing the connection.
    private func watch(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, complete, error in
            guard let self = self, conn === self.conn else { return }
            if complete || error != nil { self.fail(conn, "Server closed the connection") }
            else { self.watch(conn) }
        }
    }

    func send(_ data: Data) {
        queue.async { [weak self] in
            guard let self = self, self.ready, let conn = self.conn, self.pending < 200 else { return }
            self.pending += 1
            conn.send(content: data, completion: .contentProcessed { [weak self] error in
                self?.queue.async {
                    guard let self = self else { return }
                    self.pending -= 1
                    if let error = error { self.fail(conn, "Send error: \(error.localizedDescription)"); return }
                    self.lock.lock(); self._bytes += data.count; self.lock.unlock()
                }
            })
        }
    }

    private func fail(_ conn: NWConnection, _ message: String) {
        guard conn === self.conn else { return }
        ready = false
        conn.cancel()
        self.conn = nil
        onEvent?(.failed(message))
    }

    func stop() {
        queue.async { [weak self] in
            self?.ready = false
            self?.conn?.cancel()
            self?.conn = nil
            self?.pending = 0
        }
    }

    /// Updates the "now playing" title via the v1 admin interface (listener port).
    static func updateTitle(host: String, listenerPort: Int, password: String, title: String,
                            completion: @escaping (Bool) -> Void) {
        var c = URLComponents()
        c.scheme = "http"; c.host = host; c.port = listenerPort; c.path = "/admin.cgi"
        c.queryItems = [.init(name: "pass", value: password), .init(name: "mode", value: "updinfo"),
                        .init(name: "song", value: title)]
        guard let url = c.url else { completion(false); return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Mozilla/5.0 (ShoutcastEncoder)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { _, resp, err in
            let ok = err == nil && ((resp as? HTTPURLResponse)?.statusCode ?? 0) == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }
}
