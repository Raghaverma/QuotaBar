import Foundation
import QuotaBarDomain

/// A thin orchestration shell: resolve the manifest + credential, run the balance
/// request, hand the bytes to the interpreter. All real logic lives in the seams.
final class RelayProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor
    private let registry: RelayAdapterRegistry
    private let keychain: KeychainService
    private let session: URLSession

    init(
        descriptor: ProviderDescriptor,
        registry: RelayAdapterRegistry,
        keychain: KeychainService,
        session: URLSession = .shared
    ) {
        self.descriptor = descriptor
        self.registry = registry
        self.keychain = keychain
        self.session = session
    }

    func fetch() async throws -> UsageSnapshot {
        guard let relay = descriptor.relayConfig else {
            throw ProviderError.unavailable("Relay provider has no relay configuration")
        }
        guard let manifest = registry.manifest(id: relay.adapterID) else {
            throw ProviderError.unavailable("Unknown relay adapter: \(relay.adapterID)")
        }
        guard let baseURL = URL(string: relay.baseURL), !relay.baseURL.isEmpty else {
            throw ProviderError.unavailable("Relay base URL is empty")
        }
        guard baseURL.scheme == "https" || baseURL.host == "localhost" || baseURL.host == "127.0.0.1" else {
            throw ProviderError.unavailable("Relay URLs must use HTTPS so credentials are not sent in plaintext")
        }

        let request = try buildBalanceRequest(baseURL: baseURL, manifest: manifest, relay: relay)
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try RelayResponseInterpreter.interpret(
            data: data,
            manifest: manifest,
            providerID: descriptor.id,
            providerName: descriptor.name,
            lowRemaining: descriptor.threshold.lowRemaining
        )
    }

    private func buildBalanceRequest(
        baseURL: URL,
        manifest: RelayAdapterManifest,
        relay: RelayProviderConfig
    ) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(manifest.balanceRequest.path)
        var request = URLRequest(url: url)
        request.httpMethod = manifest.balanceRequest.method
        request.timeoutInterval = 20

        // Resolve the bearer/cookie secret from the Keychain coordinates.
        let secret = try descriptor.auth.keychainService.flatMap { service in
            try descriptor.auth.keychainAccount.flatMap { account in
                try keychain.secret(service: service, account: account)
            }
        }
        if let secret, let header = manifest.balanceRequest.authHeader {
            let scheme = manifest.balanceRequest.authScheme.map { "\($0) " } ?? ""
            request.setValue("\(scheme)\(secret)", forHTTPHeaderField: header)
        }
        if let userIDHeader = manifest.balanceRequest.userIDHeader, let userID = relay.userID {
            request.setValue(userID, forHTTPHeaderField: userIDHeader)
        }
        return request
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw ProviderError.unauthorized
        case 429: throw ProviderError.rateLimited
        default: throw ProviderError.invalidResponse("HTTP \(http.statusCode)")
        }
    }
}
