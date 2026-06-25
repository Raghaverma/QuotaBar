import Foundation

/// Loads & indexes relay manifests from the bundle's `RelayAdapters/` directory.
final class RelayAdapterRegistry: @unchecked Sendable {
    private let manifests: [String: RelayAdapterManifest]

    init(manifests: [RelayAdapterManifest]) {
        // Keep the first manifest seen for any given id rather than trapping on a
        // duplicate key (which `Dictionary(uniqueKeysWithValues:)` would do) — two
        // bundled files sharing an `id` must not crash the app at launch.
        self.manifests = Dictionary(manifests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Load every relay manifest from the bundle. SwiftPM's `.process` rule may
    /// flatten the `RelayAdapters/` directory, so we scan both that subdirectory
    /// and the bundle root, keeping only JSON that decodes as a manifest.
    static func loadFromBundle(_ bundle: Bundle = .customModule) -> RelayAdapterRegistry {
        let decoder = JSONDecoder()
        var seen: Set<String> = []
        var loaded: [RelayAdapterManifest] = []

        let candidates = (bundle.urls(forResourcesWithExtension: "json", subdirectory: "RelayAdapters") ?? [])
            + (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])

        for url in candidates {
            guard seen.insert(url.lastPathComponent).inserted,
                  let data = try? Data(contentsOf: url),
                  let manifest = try? decoder.decode(RelayAdapterManifest.self, from: data)
            else { continue }
            loaded.append(manifest)
        }
        return RelayAdapterRegistry(manifests: loaded)
    }

    func manifest(id: String) -> RelayAdapterManifest? { manifests[id] }
    var allManifests: [RelayAdapterManifest] { Array(manifests.values) }
}
