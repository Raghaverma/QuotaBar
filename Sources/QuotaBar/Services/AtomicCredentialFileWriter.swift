import Foundation

/// Writes credential files atomically while preserving the original permissions and a backup.
enum AtomicCredentialFileWriter {
    static func writeJSON(_ object: Any, to url: URL) throws {
        let manager = FileManager.default
        let exists = manager.fileExists(atPath: url.path)
        let attributes = exists ? try manager.attributesOfItem(atPath: url.path) : [:]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let backupURL = url.appendingPathExtension("quotabar-backup")

        if exists {
            if manager.fileExists(atPath: backupURL.path) {
                try manager.removeItem(at: backupURL)
            }
            try manager.copyItem(at: url, to: backupURL)
        }
        try data.write(to: url, options: .atomic)
        // Preserve the original file's permissions; for a brand-new file fall back to
        // owner-only (0600) rather than the umask default so a credential file is
        // never left group/world-readable.
        let permissions = attributes[.posixPermissions] ?? NSNumber(value: 0o600)
        try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
}
