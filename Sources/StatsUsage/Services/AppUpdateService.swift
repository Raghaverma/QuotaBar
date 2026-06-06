import Foundation
import CryptoKit
import AppKit

/// The `latest.json` manifest published as a GitHub Release asset.
struct LatestReleaseManifest: Codable, Sendable, Equatable {
    struct Asset: Codable, Sendable, Equatable {
        var url: String
        var sha256: String
        var size: Int
    }
    struct Assets: Codable, Sendable, Equatable {
        var macos_zip: Asset?
        var macos_dmg: Asset?
    }
    var version: String
    var pub_date: String
    var release_url: String
    var notes_url: String
    var assets: Assets
}

enum AppUpdateError: Error, LocalizedError {
    case checksumMismatch
    case unsupportedInstallLocation
    case noAsset
    case badManifest

    var errorDescription: String? {
        switch self {
        case .checksumMismatch: return "Downloaded update failed checksum verification."
        case .unsupportedInstallLocation: return "Updates only apply when running from an .app bundle."
        case .noAsset: return "Release manifest has no macOS asset."
        case .badManifest: return "Could not parse the release manifest."
        }
    }
}

/// Checks for, downloads, verifies, and installs updates from a GitHub-hosted
/// `latest.json`. An `actor` to serialize the multi-step update flow.
actor AppUpdateService {
    private let manifestURL: URL
    private let session: URLSession

    init(
        manifestURL: URL = URL(string: "https://github.com/Raghaverma/UsageStats/releases/latest/download/latest.json")!,
        session: URLSession = .shared
    ) {
        self.manifestURL = manifestURL
        self.session = session
    }

    /// GET the manifest and return it if it advertises a newer version than `current`.
    func fetchLatestRelease(current: String) async throws -> LatestReleaseManifest? {
        let (data, _) = try await session.data(from: manifestURL)
        guard let manifest = try? JSONDecoder().decode(LatestReleaseManifest.self, from: data) else {
            throw AppUpdateError.badManifest
        }
        return isNewer(manifest.version, than: current) ? manifest : nil
    }

    /// Download the ZIP asset and verify its checksum; returns the temp file URL.
    func prepareUpdate(_ manifest: LatestReleaseManifest) async throws -> URL {
        guard let asset = manifest.assets.macos_zip ?? manifest.assets.macos_dmg,
              let url = URL(string: asset.url) else {
            throw AppUpdateError.noAsset
        }
        let (tempURL, _) = try await session.download(from: url)
        let data = try Data(contentsOf: tempURL)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard hex.caseInsensitiveCompare(asset.sha256) == .orderedSame else {
            throw AppUpdateError.checksumMismatch
        }
        return tempURL
    }

    /// Unzips the downloaded update, replaces the running bundle, and launches the new version.
    func installUpdate(zipURL: URL) async throws {
        let mainBundleURL = Bundle.main.bundleURL
        guard mainBundleURL.pathExtension == "app" else {
            throw AppUpdateError.unsupportedInstallLocation
        }
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, tempDir.path]
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AppUpdateService",
                        code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "Failed to extract ZIP using ditto (status: \(proc.terminationStatus))"]
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        
        let newAppURL = tempDir.appendingPathComponent("StatsUsage.app")
        guard fileManager.fileExists(atPath: newAppURL.path) else {
            throw NSError(
                domain: "AppUpdateService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Extracted update did not contain StatsUsage.app"]
            )
        }
        
        let backupURL = fileManager.temporaryDirectory.appendingPathComponent("StatsUsage.app.bak-\(UUID().uuidString)")
        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.removeItem(at: backupURL)
        }
        
        try fileManager.moveItem(at: mainBundleURL, to: backupURL)
        
        do {
            try fileManager.moveItem(at: newAppURL, to: mainBundleURL)
            try? fileManager.removeItem(at: backupURL)
        } catch {
            try? fileManager.moveItem(at: backupURL, to: mainBundleURL)
            throw error
        }
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = []
        
        await MainActor.run {
            NSWorkspace.shared.openApplication(at: mainBundleURL, configuration: configuration) { _, error in
                if let error = error {
                    NSLog("Failed to relaunch application: \(error)")
                }
                Task { @MainActor in
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// Compare semantic-ish version strings ("2.2.2" vs "2.10.0") component-wise.
    nonisolated func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
