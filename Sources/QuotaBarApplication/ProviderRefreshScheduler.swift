import Foundation
/// What the scheduler needs to know about one provider to keep it fresh.
public struct ProviderRefreshScheduleDescriptor: Sendable {
    public var id: String
    public var pollIntervalSec: Int
    public var enabled: Bool
    public var refresh: @Sendable (_ forceRefresh: Bool) async -> Void
    /// Returns the provider's current consecutive-failure count for backoff.
    public var failureCount: @Sendable () -> Int

    public init(
        id: String,
        pollIntervalSec: Int,
        enabled: Bool,
        refresh: @escaping @Sendable (_ forceRefresh: Bool) async -> Void,
        failureCount: @escaping @Sendable () -> Int
    ) {
        self.id = id
        self.pollIntervalSec = pollIntervalSec
        self.enabled = enabled
        self.refresh = refresh
        self.failureCount = failureCount
    }
}

/// Keeps N providers fresh with a single coalesced, jittered, backoff-aware loop.
@MainActor
public final class ProviderRefreshScheduler {
    public typealias SleepAction = @Sendable (_ seconds: Double) async throws -> Void

    private var descriptors: [String: ProviderRefreshScheduleDescriptor] = [:]
    private var nextDueAt: [String: Date] = [:]
    private var inFlight: Set<String> = []
    private var pollLoopTask: Task<Void, Never>?
    private var pollRunID = UUID()

    private let now: @Sendable () -> Date
    private let sleepAction: SleepAction
    private let jitter: @Sendable () -> Double

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        sleepAction: @escaping SleepAction = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...20) }
    ) {
        self.now = now
        self.sleepAction = sleepAction
        self.jitter = jitter
    }

    /// (Re)start the loop with a fresh set of providers, seeding startup jitter.
    public func restart(providers: [ProviderRefreshScheduleDescriptor]) {
        stop()
        descriptors = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        let base = now()
        nextDueAt = [:]
        for p in providers where p.enabled {
            nextDueAt[p.id] = base.addingTimeInterval(jitter())
        }
        let runID = UUID()
        pollRunID = runID
        pollLoopTask = Task { [weak self] in
            await self?.pollLoop(runID: runID)
        }
    }

    public func stop() {
        pollLoopTask?.cancel()
        pollLoopTask = nil
        inFlight.removeAll()
        pollRunID = UUID()
    }

    /// Force an immediate refresh of every enabled provider.
    public func refreshNow() {
        for (id, desc) in descriptors where desc.enabled {
            startRefresh(id: id, descriptor: desc, force: true)
        }
    }

    /// Compute the earliest due time across enabled providers, excluding those in flight.
    func earliestDueAt() -> Date? {
        nextDueAt.filter { !inFlight.contains($0.key) }.values.min()
    }

    private func pollLoop(runID: UUID) async {
        while !Task.isCancelled, pollRunID == runID {
            // Prune disabled/removed providers.
            for id in nextDueAt.keys where descriptors[id]?.enabled != true {
                nextDueAt[id] = nil
            }
            guard let due = earliestDueAt() else {
                // Nothing scheduled — idle briefly, then re-check.
                try? await sleepAction(5)
                continue
            }
            let wait = max(0, due.timeIntervalSince(now()))
            if wait > 0 { try? await sleepAction(wait) }
            if Task.isCancelled || pollRunID != runID { return }

            let current = now()
            for (id, desc) in descriptors where desc.enabled {
                guard let dueAt = nextDueAt[id], dueAt <= current, !inFlight.contains(id) else { continue }
                startRefresh(id: id, descriptor: desc, force: false)
            }
        }
    }

    private func startRefresh(id: String, descriptor: ProviderRefreshScheduleDescriptor, force: Bool) {
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        Task { @MainActor [weak self] in
            await descriptor.refresh(force)
            guard let self else { return }
            self.inFlight.remove(id)
            let failures = descriptor.failureCount()
            let delay = BackoffPolicy.delaySeconds(
                baseInterval: descriptor.pollIntervalSec,
                consecutiveFailures: failures
            )
            self.nextDueAt[id] = self.now().addingTimeInterval(Double(delay))
        }
    }
}
