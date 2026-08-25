import CryptoKit
import Foundation
import Security

public enum GoogleAuthError: LocalizedError, Equatable {
    case missingClientID
    case authorizationRequired
    case invalidCallback
    case stateMismatch
    case tokenExchangeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingClientID: "Enter a Google Desktop OAuth client ID in Configure."
        case .authorizationRequired: "Connect a Google account to continue."
        case .invalidCallback: "Google returned an invalid authorization response."
        case .stateMismatch: "The OAuth response could not be verified. Please try again."
        case .tokenExchangeFailed(let message): "Google authorization failed: \(message)"
        }
    }
}

public struct OAuthAuthorizationRequest: Equatable, Sendable {
    public let url: URL
    public let verifier: String
    public let state: String
    public let redirectURI: String
}

public struct StoredGoogleCredential: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

private struct GoogleTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

public protocol CredentialStoring: Sendable {
    func load() throws -> StoredGoogleCredential?
    func save(_ credential: StoredGoogleCredential) throws
    func clear() throws
}

public final class KeychainCredentialStore: CredentialStoring, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(service: String = AppIdentity.bundleIdentifier, account: String = "google-oauth") {
        self.service = service
        self.account = account
    }

    public func load() throws -> StoredGoogleCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status) }
        return try JSONDecoder().decode(StoredGoogleCredential.self, from: data)
    }

    public func save(_ credential: StoredGoogleCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(updateStatus)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? { SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)" }
    }
}

public struct GoogleOAuthService: Sendable {
    public static let calendarReadOnlyScope = "https://www.googleapis.com/auth/calendar.readonly"

    private let session: URLSession
    private let credentialStore: CredentialStoring

    public init(session: URLSession = .shared, credentialStore: CredentialStoring = KeychainCredentialStore()) {
        self.session = session
        self.credentialStore = credentialStore
    }

    public func makeAuthorizationRequest(clientID: String, loopbackPort: UInt16) throws -> OAuthAuthorizationRequest {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GoogleAuthError.missingClientID }
        let verifier = Self.randomURLSafeString(byteCount: 48)
        let state = Self.randomURLSafeString(byteCount: 24)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let redirectURI = "http://127.0.0.1:\(loopbackPort)/oauth2callback"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.calendarReadOnlyScope),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return OAuthAuthorizationRequest(url: components.url!, verifier: verifier, state: state, redirectURI: redirectURI)
    }

    public func exchangeAuthorizationCode(_ code: String, request: OAuthAuthorizationRequest, clientID: String) async throws -> StoredGoogleCredential {
        let response = try await tokenRequest([
            "client_id": clientID,
            "code": code,
            "code_verifier": request.verifier,
            "grant_type": "authorization_code",
            "redirect_uri": request.redirectURI,
        ])
        let credential = StoredGoogleCredential(accessToken: response.accessToken, refreshToken: response.refreshToken, expiresAt: Date().addingTimeInterval(response.expiresIn))
        try credentialStore.save(credential)
        return credential
    }

    public func validAccessToken(clientID: String, now: Date = Date()) async throws -> String {
        guard var credential = try credentialStore.load() else { throw GoogleAuthError.authorizationRequired }
        if credential.expiresAt.timeIntervalSince(now) > 60 { return credential.accessToken }
        guard let refreshToken = credential.refreshToken else { throw GoogleAuthError.authorizationRequired }
        let response = try await tokenRequest([
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
        credential.accessToken = response.accessToken
        credential.refreshToken = response.refreshToken ?? refreshToken
        credential.expiresAt = now.addingTimeInterval(response.expiresIn)
        try credentialStore.save(credential)
        return credential.accessToken
    }

    public func disconnect() throws {
        try credentialStore.clear()
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key.formEncoded)=\($0.value.formEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown token endpoint error"
            throw GoogleAuthError.tokenExchangeFailed(message)
        }
        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formEncoded: String {
        addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? self
    }
}

