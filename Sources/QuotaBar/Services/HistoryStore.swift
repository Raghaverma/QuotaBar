import Foundation

/// Persists bounded usage history so sparklines and trend diagnostics survive relaunches.
final class HistoryStore: @unchecked Sendable {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        let directory = baseDirectoryURL ?? (
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
        ).appendingPathComponent("StatsUsage", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("usage-history.json")
    }

    func load() throws -> [String: [Double]] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        return try decoder.decode([String: [Double]].self, from: Data(contentsOf: fileURL))
    }

    func save(_ history: [String: [Double]]) throws {
        try encoder.encode(history).write(to: fileURL, options: .atomic)
    }
}
