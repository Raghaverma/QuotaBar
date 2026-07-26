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
            self.directoryURL = appSupport.appendingPathComponent("QuotaBar", isDirectory: true)
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
        var preservedAnything = false
        for url in [primaryURL, shadowURL, lastKnownGoodURL] {
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else { continue }
            let dropCounter = DecodeDropCounter()
            let decoder = Self.makeDecoder()
            decoder.userInfo[.decodeDropCounter] = dropCounter
            if let config = try? decoder.decode(AppConfig.self, from: data) {
                if dropCounter.droppedCount > 0 {
                    lastLoadWasLossy = true
                    // Preserve the raw bytes so nothing is silently discarded.
                    if !preservedAnything { try? data.write(to: preservedURL) }
                } else {
                    // This file decoded cleanly, so it *is* the last known good state.
                    // Promoting on read (rather than on write) is what makes the copy
                    // meaningful: writing it on every save meant a config that saved
                    // fine but fails to load would immediately destroy the only
                    // known-good copy it exists to fall back to.
                    try? data.write(to: lastKnownGoodURL, options: .atomic)
                }
                return Self.mergingNewDefaultProviders(into: config)
            } else if !preservedAnything {
                // Invalid file — stash the *first* failure. Later, also-corrupt
                // candidates must not overwrite the earliest evidence.
                try? data.write(to: preservedURL)
                preservedAnything = true
            }
        }
        return AppConfig.default
    }

    /// Add newly shipped providers without changing or re-enabling existing user entries.
    private static func mergingNewDefaultProviders(into config: AppConfig) -> AppConfig {
        var merged = config
        merged.providers = deduplicatingIDs(config.providers)
        let existingIDs = Set(merged.providers.map(\.id))
        merged.providers.append(contentsOf: ProviderDefaultCatalog.seedProviders().filter {
            !existingIDs.contains($0.id)
        })
        return merged
    }

    /// Provider `id` is the primary key of the whole app: it keys the provider map, the
    /// snapshot and history dictionaries, and the scheduler's descriptor map. A config
    /// file is user-editable and can be merged or restored by hand, so duplicates are
    /// reachable — and downstream they used to trap. Keep the first entry for each id.
    private static func deduplicatingIDs(_ providers: [ProviderDescriptor]) -> [ProviderDescriptor] {
        var seen: Set<String> = []
        return providers.filter { seen.insert($0.id).inserted }
    }

    /// Write the primary file plus a shadow copy. The last-known-good snapshot is
    /// deliberately *not* written here — `load()` promotes it only once a file has
    /// actually been read back successfully.
    func save(_ config: AppConfig) throws {
        let data = try Self.makeEncoder().encode(config)
        try data.write(to: primaryURL, options: .atomic)
        try? data.write(to: shadowURL, options: .atomic)
    }

    /// Remove all snapshots + import markers.
    func reset() throws {
        for url in [primaryURL, shadowURL, lastKnownGoodURL, preservedURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
