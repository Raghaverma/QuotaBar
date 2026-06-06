import Foundation

/// Loads & indexes relay manifests from the bundle's `RelayAdapters/` directory.
final class RelayAdapterRegistry: @unchecked Sendable {
    private let manifests: [String: RelayAdapterManifest]

    init(manifests: [RelayAdapterManifest]) {
        self.manifests = Dictionary(uniqueKeysWithValues: manifests.map { ($0.id, $0) })
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
