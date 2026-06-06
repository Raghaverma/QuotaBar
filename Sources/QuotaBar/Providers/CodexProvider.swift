import Foundation
import StatsUsageDomain

/// Reads local Codex CLI login state (`~/.codex/auth.json`) and queries the official
/// ChatGPT wham usage endpoint to report actual account quota and windows dynamically.
final class CodexProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor
    private let keychain: KeychainService
    private let authFileURL: URL

    init(descriptor: ProviderDescriptor, keychain: KeychainService, authFileURL: URL? = nil) {
        self.descriptor = descriptor
        self.keychain = keychain
        self.authFileURL = authFileURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/auth.json")
    }

    func fetch() async throws -> UsageSnapshot {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw ProviderError.missingCredential("Codex CLI login (~/.codex/auth.json)")
        }
        
        let fileData = try Data(contentsOf: authFileURL)
        guard let jsonObject = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any] else {
            throw ProviderError.invalidResponse("auth.json is malformed")
        }
        
        let account = parseAccountLabel(data: fileData)
        
        guard let tokens = jsonObject["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty else {
            throw ProviderError.missingCredential("Access token is missing in auth.json")
        }
        
        let refreshTokenVal = tokens["refresh_token"] as? String
        let accountId = tokens["account_id"] as? String
        
        var responseData: Data
        do {
            responseData = try await requestUsage(accessToken: accessToken, accountId: accountId)
        } catch ProviderError.unauthorized {
            // Access token expired; try to refresh it if we have a refresh token
            if let refresh = refreshTokenVal, !refresh.isEmpty {
                do {
                    let newTokens = try await refreshAuthToken(refreshToken: refresh)
                    try writeBack(accessToken: newTokens.accessToken, refreshToken: newTokens.newRefreshToken)
                    responseData = try await requestUsage(accessToken: newTokens.accessToken, accountId: accountId)
                } catch {
                    throw ProviderError.unauthorized
                }
            } else {
                throw ProviderError.unauthorized
            }
        }
        
        guard let root = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw ProviderError.invalidResponse("Failed to parse API usage response")
        }
        
        var windows: [UsageQuotaWindow] = []
        var primaryPct: Double?
        var secondaryPct: Double?
        
        if let rateLimit = root["rate_limit"] as? [String: Any] {
            if let primary = rateLimit["primary_window"] as? [String: Any],
               let used = primary["used_percent"] as? Double {
                let resetSec = primary["reset_at"] as? Double
                let resetDate = resetSec.map { Date(timeIntervalSince1970: $0) }
                primaryPct = 100 - used
                windows.append(UsageQuotaWindow(
                    id: "\(descriptor.id).session",
                    title: "5h",
                    remainingPercent: max(0, 100 - used),
                    usedPercent: used,
                    resetAt: resetDate,
                    kind: .session,
                    resetSource: .official
                ))
            }
            if let secondary = rateLimit["secondary_window"] as? [String: Any],
               let used = secondary["used_percent"] as? Double {
                let resetSec = secondary["reset_at"] as? Double
                let resetDate = resetSec.map { Date(timeIntervalSince1970: $0) }
                secondaryPct = 100 - used
                windows.append(UsageQuotaWindow(
                    id: "\(descriptor.id).weekly",
                    title: "Weekly",
                    remainingPercent: max(0, 100 - used),
                    usedPercent: used,
                    resetAt: resetDate,
                    kind: .weekly,
                    resetSource: .official
                ))
            }
        }
        
        // Fallback window if API parsed empty
        if windows.isEmpty {
            windows.append(UsageQuotaWindow(
                id: "\(descriptor.id).session",
                title: "Session",
                remainingPercent: 100,
                usedPercent: 0,
                resetAt: nil,
                kind: .session,
                resetSource: .localEstimate
            ))
        }
        
        let minPercent = [primaryPct, secondaryPct].compactMap { $0 }.min() ?? 100.0
        let plan = root["plan_type"] as? String ?? "unknown"
        
        return UsageSnapshot(
            source: descriptor.id,
            status: minPercent <= Double(descriptor.threshold.lowRemaining) ? .warning : .ok,
            fetchHealth: .ok,
            valueFreshness: .live,
            remaining: minPercent,
            used: 100.0 - minPercent,
            limit: 100.0,
            unit: "quota",
            note: "Plan: \(plan.capitalized)",
            quotaWindows: windows,
            sourceLabel: "API",
            accountLabel: account
        ).withDefaultResetMetadata()
    }

    private func requestUsage(accessToken: String, accountId: String?) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("HTTP \(http.statusCode)")
        }
        return data
    }

    private func refreshAuthToken(refreshToken: String) async throws -> (accessToken: String, newRefreshToken: String) {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "grant_type=refresh_token&client_id=app_EMoamEEZ73f0CkXaXp7hrann&refresh_token=\(refreshToken)"
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ProviderError.unauthorized
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw ProviderError.invalidResponse("refresh parse failed")
        }
        let newRefresh = json["refresh_token"] as? String ?? refreshToken
        return (accessToken, newRefresh)
    }

    private func writeBack(accessToken: String, refreshToken: String) throws {
        guard descriptor.officialConfig?.allowCredentialFileUpdates == true else { return }
        let fileData = try Data(contentsOf: authFileURL)
        guard var newObj = try JSONSerialization.jsonObject(with: fileData) as? [String: Any] else {
            throw ProviderError.invalidResponse("Codex credential file is malformed")
        }
        var tokens = (newObj["tokens"] as? [String: Any]) ?? [:]
        tokens["access_token"] = accessToken
        tokens["refresh_token"] = refreshToken
        newObj["tokens"] = tokens
        newObj["last_refresh"] = ISO8601DateFormatter().string(from: Date())
        try AtomicCredentialFileWriter.writeJSON(newObj, to: authFileURL)
    }

    private func parseAccountLabel(data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let email = obj["email"] as? String { return email }
        if let tokens = obj["tokens"] as? [String: Any] {
            if let email = tokens["account_email"] as? String { return email }
            if let idToken = tokens["id_token"] as? String,
               let email = parseEmailFromIdToken(idToken) {
                return email
            }
        }
        return nil
    }

    private func parseEmailFromIdToken(_ idToken: String) -> String? {
        let parts = idToken.components(separatedBy: ".")
        guard parts.count > 1 else { return nil }
        var payload = parts[1]
        
        // Base64URL decoding alignment
        let padLength = (4 - (payload.count % 4)) % 4
        payload += String(repeating: "=", count: padLength)
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["email"] as? String
    }
}
