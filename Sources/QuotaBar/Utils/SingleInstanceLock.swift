import Foundation

/// Takes an exclusive `flock` on a file in `/tmp` so only one copy of the app runs.
final class SingleInstanceLock: @unchecked Sendable {
    static let shared = SingleInstanceLock()

    private var fileDescriptor: Int32 = -1
    private let lockPath = NSTemporaryDirectory() + "com.statsusage.app.lock"

    private init() {}

    /// Returns true if this process acquired the lock (i.e. it's the first instance).
    func acquire() -> Bool {
        fileDescriptor = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard fileDescriptor != -1 else { return true }   // can't lock → don't block launch
        let result = flock(fileDescriptor, LOCK_EX | LOCK_NB)
        return result == 0
    }
}
