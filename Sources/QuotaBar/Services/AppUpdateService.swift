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
    case untrustedDownloadLocation
    case unexpectedAssetSize
    case invalidCodeSignature
    case wrongBundleIdentifier
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .checksumMismatch: return "Downloaded update failed checksum verification."
        case .unsupportedInstallLocation: return "Updates only apply when running from an .app bundle."
        case .noAsset: return "Release manifest has no macOS asset."
        case .badManifest: return "Could not parse the release manifest."
        case .untrustedDownloadLocation: return "The update points to an untrusted download location."
        case .unexpectedAssetSize: return "The downloaded update size does not match the release manifest."
        case .invalidCodeSignature: return "The downloaded application has an invalid code signature."
        case .wrongBundleIdentifier: return "The downloaded application is not StatsUsage."
        case .httpStatus(let status): return "The update server returned HTTP \(status)."
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
        guard Self.isTrustedReleaseURL(manifestURL) else {
            throw AppUpdateError.untrustedDownloadLocation
        }
        let (data, response) = try await session.data(from: manifestURL)
        try validateHTTP(response)
        guard let finalURL = response.url, Self.isTrustedReleaseURL(finalURL) else {
            throw AppUpdateError.untrustedDownloadLocation
        }
        guard let manifest = try? JSONDecoder().decode(LatestReleaseManifest.self, from: data) else {
            throw AppUpdateError.badManifest
        }
        return isNewer(manifest.version, than: current) ? manifest : nil
    }

    /// Download the ZIP asset and verify its checksum; returns the temp file URL.
    func prepareUpdate(_ manifest: LatestReleaseManifest) async throws -> URL {
        guard let asset = manifest.assets.macos_zip,
              let url = URL(string: asset.url) else {
            throw AppUpdateError.noAsset
        }
        guard Self.isTrustedReleaseURL(url) else {
            throw AppUpdateError.untrustedDownloadLocation
        }
        let (tempURL, response) = try await session.download(from: url)
        try validateHTTP(response)
        guard let finalURL = response.url, Self.isTrustedReleaseURL(finalURL) else {
            throw AppUpdateError.untrustedDownloadLocation
        }
        // Stream the file through SHA256 in 256 KB chunks to avoid loading the
        // whole ZIP into memory at once.
        let fileSize = try FileManager.default
            .attributesOfItem(atPath: tempURL.path)[.size] as? Int ?? 0
        guard fileSize == asset.size else {
            throw AppUpdateError.unexpectedAssetSize
        }
        let hex = try streamingSHA256(at: tempURL)
        guard hex.caseInsensitiveCompare(asset.sha256) == .orderedSame else {
            throw AppUpdateError.checksumMismatch
        }
        return tempURL
    }

    private func streamingSHA256(at url: URL) throws -> String {
        guard let stream = InputStream(url: url) else {
            throw CocoaError(.fileReadUnknown)
        }
        stream.open()
        defer { stream.close() }
        var hasher = SHA256()
        let bufferSize = 256 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while true {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read == 0 { break }
            if read < 0 { throw stream.streamError ?? CocoaError(.fileReadUnknown) }
            hasher.update(data: UnsafeRawBufferPointer(start: buffer, count: read))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
        guard Bundle(url: newAppURL)?.bundleIdentifier == "com.statsusage.app" else {
            throw AppUpdateError.wrongBundleIdentifier
        }
        try await verifyCodeSignature(at: newAppURL)
        
        let backupURL = fileManager.temporaryDirectory.appendingPathComponent("StatsUsage.app.bak-\(UUID().uuidString)")
        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.removeItem(at: backupURL)
        }
        
        try fileManager.moveItem(at: mainBundleURL, to: backupURL)
        
        do {
            try fileManager.moveItem(at: newAppURL, to: mainBundleURL)
            try? fileManager.removeItem(at: backupURL)
        } catch {
            do {
                try fileManager.moveItem(at: backupURL, to: mainBundleURL)
            } catch let rollbackError {
                throw NSError(
                    domain: "AppUpdateService",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Update failed and rollback also failed: \(rollbackError.localizedDescription)"]
                )
            }
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

    private func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw AppUpdateError.httpStatus(http.statusCode)
        }
    }

    private func verifyCodeSignature(at appURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", appURL.path]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AppUpdateError.invalidCodeSignature)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated static func isTrustedReleaseURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com"
            || host == "objects.githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
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
