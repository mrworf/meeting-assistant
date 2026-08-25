import AppKit
import MeetingAssistantCore
import Network

struct OAuthCallbackResult: Sendable {
    let code: String
    let request: OAuthAuthorizationRequest
}

final class LoopbackOAuthCoordinator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MeetingAssistant.OAuthLoopback")

    func authorize(clientID: String, oauth: GoogleOAuthService) async throws -> OAuthCallbackResult {
        let listener = try NWListener(using: .tcp, on: .any)
        return try await withCheckedThrowingContinuation { continuation in
            let session = CallbackSession(listener: listener, continuation: continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port else { session.fail(GoogleAuthError.invalidCallback); return }
                    do {
                        let request = try oauth.makeAuthorizationRequest(clientID: clientID, loopbackPort: port.rawValue)
                        session.request = request
                        DispatchQueue.main.async {
                            if !NSWorkspace.shared.open(request.url) { session.fail(GoogleAuthError.invalidCallback) }
                        }
                    } catch { session.fail(error) }
                case .failed(let error): session.fail(error)
                case .cancelled: break
                default: break
                }
            }
            listener.newConnectionHandler = { connection in session.handle(connection) }
            listener.start(queue: queue)
        }
    }
}

private final class CallbackSession: @unchecked Sendable {
    private let lock = NSLock()
    private let listener: NWListener
    private var continuation: CheckedContinuation<OAuthCallbackResult, Error>?
    var request: OAuthAuthorizationRequest?

    init(listener: NWListener, continuation: CheckedContinuation<OAuthCallbackResult, Error>) {
        self.listener = listener
        self.continuation = continuation
    }

    func handle(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "MeetingAssistant.OAuthConnection"))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error { self.fail(error); return }
            guard let data,
                  let firstLine = String(data: data, encoding: .utf8)?.components(separatedBy: "\r\n").first,
                  let target = firstLine.split(separator: " ").dropFirst().first,
                  let components = URLComponents(string: "http://127.0.0.1\(target)"),
                  let request = self.request
            else { self.respond(connection, success: false); self.fail(GoogleAuthError.invalidCallback); return }
            let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            guard values["state"] == request.state else { self.respond(connection, success: false); self.fail(GoogleAuthError.stateMismatch); return }
            guard let code = values["code"], !code.isEmpty else { self.respond(connection, success: false); self.fail(GoogleAuthError.invalidCallback); return }
            self.respond(connection, success: true)
            self.finish(.success(OAuthCallbackResult(code: code, request: request)))
        }
    }

    func fail(_ error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<OAuthCallbackResult, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<OAuthCallbackResult, Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        guard let continuation else { return }
        listener.cancel()
        continuation.resume(with: result)
    }

    private func respond(_ connection: NWConnection, success: Bool) {
        let message = success ? "Authorization complete. You can close this window and return to Meeting Assistant." : "Authorization failed. Return to Meeting Assistant and try again."
        let body = "<html><body style='font-family:-apple-system;padding:40px'><h2>Meeting Assistant</h2><p>\(message)</p></body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
