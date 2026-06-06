import Foundation
import StatsUsageDomain

/// Reads local Claude CLI/App login credentials and queries Anthropic platforms to report account quota.
final class ClaudeProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor
    private let session: URLSession
    private let refreshBuffer: TimeInterval = 5 * 60
    private let homeDirectory: () -> String

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        homeDirectory: @escaping () -> String = { NSHomeDirectory() }
    ) {
        self.descriptor = descriptor
        self.session = session
        self.homeDirectory = homeDirectory
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        try await loadSnapshot(forceRefresh: forceRefresh)
    }

    private func loadSnapshot(forceRefresh: Bool) async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? OfficialProviderConfig(sourceMode: .api)
        switch official.sourceMode {
        case .api:
            return try await loadFromAPI(forceRefresh: forceRefresh)
        case .cli:
            return try await loadFromCLI()
        case .web:
            throw ProviderError.unavailable("Claude web source mode is not supported in this version of StatsUsage")
        case .auto:
            do {
                return try await loadFromAPI(forceRefresh: forceRefresh)
            } catch {
                return try await loadFromCLI()
            }
        }
    }

    private func loadFromAPI(forceRefresh: Bool) async throws -> UsageSnapshot {
        var credentials = try loadCredentials()
        guard !credentials.inferenceOnly else {
            throw ProviderError.unauthorizedDetail("inference-only token cannot read Claude quota")
        }

        if needsRefresh(expiresAtMs: credentials.expiresAtMs) {
            credentials = try await refresh(credentials: credentials)
        }

        let (data, usageResponse) = try await requestOAuthUsage(accessToken: credentials.accessToken)
        return try Self.parseClaudeSnapshot(
            root: data,
            response: usageResponse,
            descriptor: descriptor,
            sourceLabel: "API",
            accountLabel: credentials.accountLabel,
            planHint: credentials.subscriptionType
        )
    }

    private func loadFromCLI() async throws -> UsageSnapshot {
        try runClaudeCLIUsage()
    }

    private func loadCredentials() throws -> ClaudeCredentials {
        let path = "\(homeDirectory())/.claude/.credentials.json"
        if FileManager.default.fileExists(atPath: path),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let credentials = parseClaudeCredentials(json: json, source: .file(path)) {
            return credentials
        }

        if let raw = readKeychainSecret(service: "Claude Code-credentials"),
           let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let credentials = parseClaudeCredentials(json: json, source: .keychain) {
            return credentials
        }

        if let token = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return ClaudeCredentials(
                accessToken: token,
                refreshToken: nil,
                expiresAtMs: nil,
                subscriptionType: nil,
                scopes: [],
                source: .environment,
                inferenceOnly: true
            )
        }

        throw ProviderError.missingCredential("~/.claude/.credentials.json")
    }

    private func parseClaudeCredentials(json: [String: Any], source: ClaudeCredentialSource) -> ClaudeCredentials? {
        guard let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = OfficialValueParser.string(oauth["accessToken"]) else {
            return nil
        }
        let refreshToken = OfficialValueParser.string(oauth["refreshToken"])
        let expiresAtMs = OfficialValueParser.double(oauth["expiresAt"])
        let subscriptionType = OfficialValueParser.string(oauth["subscriptionType"])
        let scopes = (oauth["scopes"] as? [String]) ?? []
        let inferenceOnly = !scopes.isEmpty && !scopes.contains("user:profile")
        return ClaudeCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAtMs: expiresAtMs,
            subscriptionType: subscriptionType,
            scopes: scopes,
            source: source,
            inferenceOnly: inferenceOnly
        )
    }

    private func readKeychainSecret(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func needsRefresh(expiresAtMs: Double?) -> Bool {
        guard let expiresAtMs else { return false }
        let nowMs = Date().timeIntervalSince1970 * 1000
        return nowMs + 5 * 60 * 1000 >= expiresAtMs
    }

    private func refresh(credentials: ClaudeCredentials) async throws -> ClaudeCredentials {
        guard let refreshToken = credentials.refreshToken else {
            throw ProviderError.unauthorized
        }

        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            "scope": "user:profile user:inference user:sessions:claude_code user:mcp_servers"
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Claude refresh non-http response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Claude refresh HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Claude refresh response decode failed")
        }
        guard let accessToken = OfficialValueParser.string(json["access_token"] ?? json["accessToken"]),
              !accessToken.isEmpty else {
            throw ProviderError.invalidResponse("missing Claude refresh access_token")
        }

        var updated = credentials
        updated.accessToken = accessToken
        updated.refreshToken = OfficialValueParser.string(json["refresh_token"]) ?? credentials.refreshToken
        if let expiresIn = OfficialValueParser.double(json["expires_in"]) {
            updated.expiresAtMs = Date().timeIntervalSince1970 * 1000 + expiresIn * 1000
        }
        if case let .file(path) = credentials.source {
            try persist(credentials: updated, path: path)
        }
        return updated
    }

    private func persist(credentials: ClaudeCredentials, path: String) throws {
        guard descriptor.officialConfig?.allowCredentialFileUpdates == true else { return }
        let url = URL(fileURLWithPath: path)
        let fileData = try Data(contentsOf: url)
        guard var json = try JSONSerialization.jsonObject(with: fileData) as? [String: Any] else {
            throw ProviderError.invalidResponse("Claude credential file is malformed")
        }
        
        var oauth = (json["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauth["accessToken"] = credentials.accessToken
        oauth["refreshToken"] = credentials.refreshToken
        oauth["expiresAt"] = credentials.expiresAtMs
        oauth["subscriptionType"] = credentials.subscriptionType
        json["claudeAiOauth"] = oauth
        
        try AtomicCredentialFileWriter.writeJSON(json, to: url)
    }

    private func requestOAuthUsage(accessToken: String) async throws -> ([String: Any], HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("StatsUsage", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
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
            throw ProviderError.invalidResponse("http \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("oauth usage decode failed")
        }
        return (json, http)
    }

    private func runClaudeCLIUsage() throws -> UsageSnapshot {
        guard let executable = resolveClaudeExecutablePath() else {
            throw ProviderError.unavailable("Unable to locate claude CLI.")
        }
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")

        guard let result = Self.runCommand(
            executable: executable,
            arguments: ["/usage", "--allowed-tools", ""],
            environment: env,
            timeout: 25
        ) else {
            throw ProviderError.commandFailed("claude /usage failed to start")
        }

        let combinedOutput = "\(result.stdout)\n\(result.stderr)"
        if Self.looksLikeMissingClaudeSubscription(text: combinedOutput) {
            throw ProviderError.unavailable("Claude subscription required")
        }
        guard result.status == 0 || !result.stdout.isEmpty else {
            throw ProviderError.commandFailed(result.stderr.isEmpty ? "claude /usage failed" : result.stderr)
        }

        do {
            return try Self.parseClaudeCLIOutput(result.stdout, descriptor: descriptor)
        } catch {
            let lower = result.stdout.lowercased()
            if lower.contains("cost") || lower.contains("api usage billing") || lower.contains("subscription required") {
                if let costResult = Self.runCommand(
                    executable: executable,
                    arguments: ["/cost", "--allowed-tools", ""],
                    environment: env,
                    timeout: 25
                ), !costResult.stdout.isEmpty {
                    return Self.parseClaudeCostOutput(costResult.stdout, descriptor: descriptor)
                }
            }
            throw error
        }
    }

    internal static func parseClaudeCLIOutput(_ text: String, descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        let clean = stripANSICodes(text)
        if clean.lowercased().contains("token_expired") {
            throw ProviderError.unauthorized
        }
        if looksLikeMissingClaudeSubscription(text: clean) {
            throw ProviderError.unavailable("Claude subscription required")
        }

        guard let sessionRemaining = extractClaudePercent(label: "Current session", text: clean) else {
            throw ProviderError.invalidResponse("missing Claude current session usage")
        }

        let weeklyRemaining = extractClaudePercent(label: "Current week", text: clean)
        let sessionReset = extractClaudeReset(label: "Current session", text: clean)
        let weeklyReset = extractClaudeReset(label: "Current week", text: clean)

        var windows: [UsageQuotaWindow] = [
            UsageQuotaWindow(
                id: "\(descriptor.id)-session",
                title: "Session",
                remainingPercent: Double(sessionRemaining),
                usedPercent: Double(max(0, 100 - sessionRemaining)),
                resetAt: sessionReset,
                kind: .session
            )
        ]
        if let weeklyRemaining {
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-weekly",
                    title: "Weekly",
                    remainingPercent: Double(weeklyRemaining),
                    usedPercent: Double(max(0, 100 - weeklyRemaining)),
                    resetAt: weeklyReset,
                    kind: .weekly
                )
            )
        }

        let remaining = windows.map(\.remainingPercent).min() ?? Double(sessionRemaining)
        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "Session \(sessionRemaining)% | Weekly \(weeklyRemaining ?? 0)%",
            quotaWindows: windows,
            sourceLabel: "CLI",
            accountLabel: nil,
            extras: [:],
            rawMeta: [:]
        ).withDefaultResetMetadata()
    }

    internal static func parseClaudeCostOutput(_ text: String, descriptor: ProviderDescriptor) -> UsageSnapshot {
        let clean = stripANSICodes(text)
        let totalCost = extractDollarValue(after: "Total cost:", text: clean) ?? 0
        return UsageSnapshot(
            source: descriptor.id,
            status: .ok,
            remaining: nil,
            used: totalCost,
            limit: nil,
            unit: "USD",
            updatedAt: Date(),
            note: "Extra usage cost $\(String(format: "%.2f", totalCost))",
            quotaWindows: [],
            sourceLabel: "CLI",
            accountLabel: nil,
            extras: ["extraUsageCostUSD": String(format: "%.2f", totalCost)],
            rawMeta: [:]
        ).withDefaultResetMetadata()
    }

    internal static func parseClaudeSnapshot(
        root: [String: Any],
        response: HTTPURLResponse? = nil,
        descriptor: ProviderDescriptor,
        sourceLabel: String,
        accountLabel: String?,
        planHint: String?,
        receivedAt: Date = Date()
    ) throws -> UsageSnapshot {
        var windows: [UsageQuotaWindow] = []
        let clockSkew = response.flatMap { Self.calculateClockSkew(response: $0, receivedAt: receivedAt) }

        if let fiveHour = root["five_hour"] as? [String: Any],
           let used = OfficialValueParser.double(fiveHour["utilization"] ?? fiveHour["used_percent"]) {
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-session",
                    title: "5h",
                    remainingPercent: max(0, 100 - used),
                    usedPercent: used,
                    resetAt: applyClockSkew(
                        OfficialValueParser.isoDate(OfficialValueParser.string(fiveHour["resets_at"])),
                        skew: clockSkew
                    ),
                    kind: .session
                )
            )
        }
        if let sevenDay = root["seven_day"] as? [String: Any],
           let used = OfficialValueParser.double(sevenDay["utilization"] ?? sevenDay["used_percent"]) {
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-weekly",
                    title: "Weekly",
                    remainingPercent: max(0, 100 - used),
                    usedPercent: used,
                    resetAt: applyClockSkew(
                        OfficialValueParser.isoDate(OfficialValueParser.string(sevenDay["resets_at"])),
                        skew: clockSkew
                    ),
                    kind: .weekly
                )
            )
        }

        var parsedSevenDayKeys: [String] = []
        for key in root.keys.sorted() where key.hasPrefix("seven_day_") {
            guard let item = root[key] as? [String: Any],
                  let used = OfficialValueParser.double(item["utilization"] ?? item["used_percent"]) else {
                continue
            }
            parsedSevenDayKeys.append(key)
            let title = normalizedSevenDayWindowTitle(for: key)
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-\(key)",
                    title: title,
                    remainingPercent: max(0, 100 - used),
                    usedPercent: used,
                    resetAt: applyClockSkew(
                        OfficialValueParser.isoDate(OfficialValueParser.string(item["resets_at"])),
                        skew: clockSkew
                    ),
                    kind: .modelWeekly
                )
            )
        }

        let extraUsage = root["extra_usage"] as? [String: Any]
        let extraCost = OfficialValueParser.double(extraUsage?["used_credits"])
        let extraLimit = OfficialValueParser.double(extraUsage?["monthly_limit"])

        if looksLikeMissingClaudeSubscription(root: root, windows: windows, planHint: planHint, extraCost: extraCost, extraLimit: extraLimit) {
            throw ProviderError.unavailable("Claude subscription required")
        }

        guard !windows.isEmpty || extraCost != nil else {
            throw ProviderError.invalidResponse("missing Claude usage windows")
        }

        let remaining = windows.map(\.remainingPercent).min()
        let note = buildClaudeNote(windows: windows, extraCost: extraCost, extraLimit: extraLimit, planHint: planHint)
        var extras: [String: String] = [:]
        if let planHint {
            extras["planType"] = planHint
        }
        if let extraCost {
            extras["extraUsageCost"] = String(format: "%.2f", extraCost)
        }
        if let extraLimit {
            extras["extraUsageLimit"] = String(format: "%.2f", extraLimit)
        }
        var rawMeta = extras
        if !parsedSevenDayKeys.isEmpty {
            rawMeta["claude.parsedSevenDayKeys"] = parsedSevenDayKeys.joined(separator: ",")
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: (remaining ?? 100) <= Double(descriptor.threshold.lowRemaining) ? .warning : .ok,
            remaining: remaining,
            used: remaining.map { 100 - $0 },
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: note,
            quotaWindows: windows,
            sourceLabel: sourceLabel,
            accountLabel: accountLabel,
            extras: extras,
            rawMeta: rawMeta
        ).withDefaultResetMetadata()
    }

    private static func calculateClockSkew(response: HTTPURLResponse, receivedAt: Date) -> TimeInterval? {
        if let dateString = response.allHeaderFields["Date"] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let serverDate = formatter.date(from: dateString) {
                return serverDate.timeIntervalSince(receivedAt)
            }
        }
        return nil
    }

    private static func applyClockSkew(_ date: Date?, skew: TimeInterval?) -> Date? {
        guard let date = date, let skew = skew else { return date }
        return date.addingTimeInterval(-skew)
    }

    private static func buildClaudeNote(windows: [UsageQuotaWindow], extraCost: Double?, extraLimit: Double?, planHint: String?) -> String {
        var parts: [String] = []
        if let planHint {
            parts.append("Plan: \(planHint.capitalized)")
        }
        for window in windows.prefix(3) {
            parts.append("\(window.title) \(Int(window.remainingPercent.rounded()))%")
        }
        if let extraCost {
            if let extraLimit, extraLimit > 0 {
                parts.append("Extra $\(String(format: "%.2f", extraCost))/$\(String(format: "%.2f", extraLimit))")
            } else {
                parts.append("Extra $\(String(format: "%.2f", extraCost))")
            }
        }
        return parts.joined(separator: " | ")
    }

    private static func normalizedSevenDayWindowTitle(for key: String) -> String {
        switch key {
        case "seven_day_sonnet_only":
            return "Sonnet only"
        case "seven_day_claude_design":
            return "Claude Design"
        default:
            let raw = key.replacingOccurrences(of: "seven_day_", with: "")
            let words = raw
                .split(separator: "_")
                .map { segment in
                    let lower = segment.lowercased()
                    if lower == "claude" {
                        return "Claude"
                    }
                    return lower.prefix(1).uppercased() + lower.dropFirst()
                }
            return words.joined(separator: " ")
        }
    }

    private func resolveClaudeExecutablePath() -> String? {
        let manager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["CLAUDE_CLI_PATH"],
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
            "/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude"
        ].compactMap { $0 }
        let envCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
            .split(separator: ":")
            .map { "\($0)/claude" }
        for path in candidates + envCandidates where manager.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func stripANSICodes(_ text: String) -> String {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func extractClaudePercent(label: String, text: String) -> Int? {
        let lines = text.components(separatedBy: .newlines)
        let target = label.lowercased()
        for (index, line) in lines.enumerated() where line.lowercased().contains(target) {
            let window = lines.dropFirst(index).prefix(12)
            for candidate in window {
                if let match = candidate.range(of: #"\b([0-9]{1,3})%\s+(left|used)\b"#, options: .regularExpression) {
                    let raw = String(candidate[match])
                    if let number = Int(raw.components(separatedBy: "%").first ?? "") {
                        if raw.lowercased().contains("used") {
                            return max(0, 100 - number)
                        }
                        return number
                    }
                }
            }
        }
        return nil
    }

    private static func extractClaudeReset(label: String, text: String) -> Date? {
        let lines = text.components(separatedBy: .newlines)
        let target = label.lowercased()
        for (index, line) in lines.enumerated() where line.lowercased().contains(target) {
            let window = lines.dropFirst(index).prefix(12)
            for candidate in window {
                guard candidate.lowercased().contains("reset") else { continue }
                if let date = OfficialValueParser.isoDate(extractISODate(from: candidate)) {
                    return date
                }
            }
        }
        return nil
    }

    private static func extractISODate(from text: String) -> String? {
        if let match = text.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z"#, options: .regularExpression) {
            return String(text[match])
        }
        return nil
    }

    private static func extractDollarValue(after label: String, text: String) -> Double? {
        guard let range = text.range(of: label) else { return nil }
        let suffix = text[range.upperBound...]
        if let match = suffix.range(of: #"\$([0-9]+(?:\.[0-9]+)?)"#, options: .regularExpression) {
            return Double(String(suffix[match]).replacingOccurrences(of: "$", with: ""))
        }
        return nil
    }

    private static func looksLikeMissingClaudeSubscription(text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "subscription required",
            "subscription plan",
            "requires subscription",
            "no active subscription",
            "upgrade to claude",
            "upgrade your plan",
            "billing required"
        ]
        return markers.contains(where: { lower.contains($0) })
    }

    private static func looksLikeMissingClaudeSubscription(
        root: [String: Any],
        windows: [UsageQuotaWindow],
        planHint: String?,
        extraCost: Double?,
        extraLimit: Double?
    ) -> Bool {
        if let planHint, !planHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if extraCost != nil || extraLimit != nil {
            return false
        }

        if containsSubscriptionMarker(in: root) {
            return true
        }

        guard !windows.isEmpty else { return false }
        let allUnused = windows.allSatisfy { $0.usedPercent <= 0.001 && $0.remainingPercent >= 99.999 }
        let noResetDates = windows.allSatisfy { $0.resetAt == nil }
        return allUnused && noResetDates
    }

    private static func containsSubscriptionMarker(in value: Any) -> Bool {
        if let string = value as? String {
            return looksLikeMissingClaudeSubscription(text: string)
        }
        if let dict = value as? [String: Any] {
            return dict.contains { containsSubscriptionMarker(in: $0.key) || containsSubscriptionMarker(in: $0.value) }
        }
        if let array = value as? [Any] {
            return array.contains { containsSubscriptionMarker(in: $0) }
        }
        return false
    }

    private static func runCommand(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 25
    ) -> ShellCommandResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let env = environment {
            process.environment = env
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: outData, encoding: .utf8) ?? ""
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            return ShellCommandResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
        } catch {
            return nil
        }
    }
}

// MARK: - Shell Helper

private struct ShellCommandResult {
    let stdout: String
    let stderr: String
    let status: Int32
}

// MARK: - Value Parsing Helper

private struct OfficialValueParser {
    static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let i = value as? Int { return String(i) }
        return nil
    }
    static func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let s = value as? String, let d = Double(s) { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
    static func isoDate(_ value: String?) -> Date? {
        guard let value = value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: value) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    static func epochDate(seconds value: Any?) -> Date? {
        guard let s = double(value) else { return nil }
        return Date(timeIntervalSince1970: s)
    }
}

// MARK: - Local Models

private struct ClaudeCredentials {
    var accessToken: String
    var refreshToken: String?
    var expiresAtMs: Double?
    var subscriptionType: String?
    var scopes: [String]
    var source: ClaudeCredentialSource
    var inferenceOnly: Bool

    var accountLabel: String? {
        guard let claims = decodeJWTPayload(accessToken) else { return nil }
        return OfficialValueParser.string(claims["email"] ?? claims["emailAddress"])
    }

    private func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

private enum ClaudeCredentialSource {
    case file(String)
    case keychain
    case environment
}
