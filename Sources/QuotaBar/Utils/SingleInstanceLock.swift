import Foundation

/// Takes an exclusive `flock` on a file in `/tmp` so only one copy of the app runs.
final class SingleInstanceLock: @unchecked Sendable {
    static let shared = SingleInstanceLock()

    private var fileDescriptor: Int32 = -1
    private let lockPath = NSTemporaryDirectory() + "com.quotabar.app.lock"

    private init() {}

    /// Returns true if this process acquired the lock (i.e. it's the first instance).
    func acquire() -> Bool {
        fileDescriptor = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard fileDescriptor != -1 else { return true }   // can't lock → don't block launch
        let result = flock(fileDescriptor, LOCK_EX | LOCK_NB)
        return result == 0
    }

    /// Drop the lock so a successor process can take it. Required before relaunching
    /// ourselves during an update: the replacement starts while this process is still
    /// alive, and would otherwise see the lock held and quit immediately.
    func release() {
        guard fileDescriptor != -1 else { return }
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }
}
