import Foundation

/// Persists `AppConfig` as non-secret JSON, engineered to never lose user state:
/// writes a primary file plus shadow/last-known-good copies, and on load tries each
/// in order before falling back to defaults.
final class ConfigStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let directoryURL: URL
    private(set) var lastLoadWasLossy = false

    private var primaryURL: URL { directoryURL.appendingPathComponent("config.json") }
    private var shadowURL: URL { directoryURL.appendingPathComponent("config.shadow.json") }
    private var lastKnownGoodURL: URL { directoryURL.appendingPathComponent("config.lkg.json") }
    private var preservedURL: URL { directoryURL.appendingPathComponent("config.preserved.json") }

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let baseDirectoryURL {
            self.directoryURL = baseDirectoryURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directoryURL = appSupport.appendingPathComponent("StatsUsage", isDirectory: true)
        }
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    /// Try every snapshot in order, repairing along the way; return default if all fail.
    func load() throws -> AppConfig {
        lastLoadWasLossy = false
        for url in [primaryURL, shadowURL, lastKnownGoodURL] {
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else { continue }
            AppConfig.lastDecodeDroppedCount = 0
            if let config = try? Self.makeDecoder().decode(AppConfig.self, from: data) {
                if AppConfig.lastDecodeDroppedCount > 0 {
                    lastLoadWasLossy = true
                    // Preserve the raw bytes so nothing is silently discarded.
                    try? data.write(to: preservedURL)
                }
                return Self.mergingNewDefaultProviders(into: config)
            } else {
                // Invalid file — stash it before moving on.
                try? data.write(to: preservedURL)
            }
        }
        return AppConfig.default
    }

    /// Add newly shipped providers without changing or re-enabling existing user entries.
    private static func mergingNewDefaultProviders(into config: AppConfig) -> AppConfig {
        var merged = config
        let existingIDs = Set(config.providers.map(\.id))
        merged.providers.append(contentsOf: ProviderDefaultCatalog.seedProviders().filter {
            !existingIDs.contains($0.id)
        })
        return merged
    }

    /// Write the primary file plus shadow and last-known-good copies.
    func save(_ config: AppConfig) throws {
        let data = try Self.makeEncoder().encode(config)
        try data.write(to: primaryURL, options: .atomic)
        try? data.write(to: shadowURL, options: .atomic)
        try? data.write(to: lastKnownGoodURL, options: .atomic)
    }

    /// Remove all snapshots + import markers.
    func reset() throws {
        for url in [primaryURL, shadowURL, lastKnownGoodURL, preservedURL] {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }
}
