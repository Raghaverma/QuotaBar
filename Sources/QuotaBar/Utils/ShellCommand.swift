import Foundation

struct ShellCommandResult {
    let stdout: String
    let stderr: String
    let status: Int32
    let timedOut: Bool
}

/// Runs a child process to completion with a hard timeout, draining both pipes as data
/// arrives.
///
/// The naive shape — `waitUntilExit()` and *then* `readDataToEndOfFile()` — deadlocks
/// whenever the child writes more than the OS pipe buffer (~64 KB): the child blocks in
/// `write()` waiting for a reader while we block waiting for it to exit. Concentrating
/// process execution here means that hazard is fixed once instead of re-introduced at
/// each call site.
enum ShellCommand {
    /// Returns `nil` only if the process could not be started at all.
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 25
    ) -> ShellCommandResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let stdoutBox = PipeAccumulator()
        let stderrBox = PipeAccumulator()
        outPipe.fileHandleForReading.readabilityHandler = { stdoutBox.append($0.availableData) }
        errPipe.fileHandleForReading.readabilityHandler = { stderrBox.append($0.availableData) }

        let semaphore = DispatchSemaphore(value: 0)
        // Set before `run()` so a process that exits immediately still signals us.
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let timedOut = semaphore.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if semaphore.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        return ShellCommandResult(
            stdout: String(data: stdoutBox.collected(), encoding: .utf8) ?? "",
            stderr: String(data: stderrBox.collected(), encoding: .utf8) ?? "",
            status: process.terminationStatus,
            timedOut: timedOut
        )
    }

    /// `run` blocks its thread, so callers in async contexts hop off the cooperative
    /// pool rather than tying up one of its limited threads.
    static func runAsync(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 25
    ) async -> ShellCommandResult? {
        await Task.detached(priority: .utility) {
            run(executable: executable, arguments: arguments, environment: environment, timeout: timeout)
        }.value
    }
}

/// Thread-safe byte accumulator for draining a `Pipe` concurrently with execution.
private final class PipeAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func collected() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
