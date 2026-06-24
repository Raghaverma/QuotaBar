import Foundation

/// One historical reading: the remaining-quota percent observed at a point in time.
/// Carrying the real timestamp (rather than assuming a constant poll interval) is what
/// lets day-bucketed views and pace estimates use actual elapsed time.
struct HistorySample: Codable, Equatable, Sendable {
    var at: Date
    var remainingPercent: Double
}

/// Persists bounded usage history so sparklines and trend diagnostics survive relaunches.
final class HistoryStore: @unchecked Sendable {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        let directory = baseDirectoryURL ?? (
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
        ).appendingPathComponent("QuotaBar", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("usage-history.json")
    }

    /// Returns `[:]` if the file is absent *or* in the pre-timestamp format — this is a
    /// rebuildable cache, so starting fresh beats fabricating timestamps for old samples.
    func load() throws -> [String: [HistorySample]] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        if let decoded = try? decoder.decode([String: [HistorySample]].self, from: data) {
            return decoded
        }
        return [:]
    }

    func save(_ history: [String: [HistorySample]]) throws {
        try encoder.encode(history).write(to: fileURL, options: .atomic)
    }
}
