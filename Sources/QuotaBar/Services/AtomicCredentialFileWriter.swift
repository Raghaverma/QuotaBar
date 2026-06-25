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
            // The backup is a second plaintext copy of OAuth tokens; lock it down
            // independently of whatever permissions copyItem preserved.
            try manager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: backupURL.path)
        }

        // Write to a sibling temp file, chmod it owner-only, then rename into place —
        // writing straight to `url` with .atomic creates the temp file at the umask
        // default (typically 0644) and only chmods after the rename, leaving a brief
        // world-readable window for brand-new credential files.
        let tempURL = url.appendingPathExtension("quotabar-tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)
        let permissions = attributes[.posixPermissions] ?? NSNumber(value: 0o600)
        try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: tempURL.path)
        _ = try manager.replaceItemAt(url, withItemAt: tempURL, options: .usingNewMetadataOnly)
    }
}
