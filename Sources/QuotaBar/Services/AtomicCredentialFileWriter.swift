import Foundation

/// Writes credential files atomically while preserving the original permissions and a backup.
enum AtomicCredentialFileWriter {
    static func writeJSON(_ object: Any, to url: URL) throws {
        let manager = FileManager.default
        let exists = manager.fileExists(atPath: url.path)
        let attributes = exists ? try manager.attributesOfItem(atPath: url.path) : [:]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let backupURL = url.appendingPathExtension("statsusage-backup")

        if exists {
            if manager.fileExists(atPath: backupURL.path) {
                try manager.removeItem(at: backupURL)
            }
            try manager.copyItem(at: url, to: backupURL)
        }
        try data.write(to: url, options: .atomic)
        if let permissions = attributes[.posixPermissions] {
            try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }
}
