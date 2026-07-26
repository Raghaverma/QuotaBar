import XCTest
import QuotaBarDomain
@testable import QuotaBar
@testable import QuotaBarApplication

/// Regression tests for the refresh scheduler's tolerance of malformed input and
/// for late-completing refreshes.
@MainActor
final class ProviderRefreshSchedulerTests: XCTestCase {

    private func descriptor(
        id: String,
        interval: Int = 300,
        enabled: Bool = true
    ) -> ProviderRefreshScheduleDescriptor {
        ProviderRefreshScheduleDescriptor(
            id: id,
            pollIntervalSec: interval,
            enabled: enabled,
            refresh: { _ in },
            failureCount: { 0 }
        )
    }

    /// A hand-edited or partially-merged `config.json` can contain two provider
    /// entries sharing an `id`. Building the descriptor map with
    /// `Dictionary(uniqueKeysWithValues:)` trapped on that, crashing at launch.
    func testDuplicateProviderIDsDoNotTrap() {
        let scheduler = ProviderRefreshScheduler(
            now: { Date(timeIntervalSince1970: 0) },
            sleepAction: { _ in try await Task.sleep(nanoseconds: 1_000_000) },
            jitter: { 0 }
        )
        scheduler.restart(providers: [
            descriptor(id: "codex", interval: 300),
            descriptor(id: "codex", interval: 60)
        ])
        // Reaching here without a trap is the assertion; the last entry wins.
        XCTAssertNotNil(scheduler.earliestDueAt())
        scheduler.stop()
    }

    /// If the user shortens a provider's poll interval while a refresh is in flight,
    /// `restart` seeds a fresh due time for the new schedule — and the late completion
    /// must not overwrite it with a delay derived from the *old*, longer interval.
    /// (Unlike a removed provider, which the poll loop prunes, this one stays enabled,
    /// so nothing else corrects the stale due time.)
    func testLateRefreshDoesNotApplyStaleIntervalAfterReschedule() async {
        let base = Date(timeIntervalSince1970: 0)
        let scheduler = ProviderRefreshScheduler(
            now: { base },
            sleepAction: { _ in try await Task.sleep(nanoseconds: 1_000_000) },
            jitter: { 0 }
        )
        let started = SendableFlag()
        let slow = ProviderRefreshScheduleDescriptor(
            id: "p",
            pollIntervalSec: 900,          // old, long interval
            enabled: true,
            refresh: { _ in
                started.set()
                try? await Task.sleep(nanoseconds: 300_000_000)
            },
            failureCount: { 0 }
        )
        scheduler.restart(providers: [slow])
        scheduler.refreshNow()
        while !started.isSet { await Task.yield() }

        // User switches this provider to a much shorter interval mid-refresh.
        scheduler.restart(providers: [descriptor(id: "p", interval: 60)])
        // Outlast the in-flight refresh so its completion has run.
        try? await Task.sleep(nanoseconds: 600_000_000)

        // The provider was due immediately, so the loop legitimately re-runs it and
        // reschedules — but always on the *new* 60s interval. A due time further out
        // than that means the late completion applied the stale 900s interval.
        let due = try? XCTUnwrap(scheduler.earliestDueAt())
        XCTAssertLessThanOrEqual(
            due ?? .distantFuture, base.addingTimeInterval(60),
            "late completion of a refresh started under the old 900s interval must not "
            + "push the due time out past the newly configured 60s interval"
        )
        scheduler.stop()
    }
}

/// Minimal thread-safe flag usable from a `@Sendable` closure.
private final class SendableFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// `application/x-www-form-urlencoded` bodies must escape every character that is
/// reserved in a form body. OAuth refresh tokens and client secrets routinely
/// contain `+`, `/`, `=` and `&`.
final class FormURLEncodingTests: XCTestCase {

    func testEscapesFormReservedCharacters() {
        let body = FormURLEncoding.body(["refresh_token": "abc+def/ghi=jkl&mno"])
        XCTAssertEqual(body, "refresh_token=abc%2Bdef%2Fghi%3Djkl%26mno")
    }

    /// `+` must be escaped: a form-decoder turns a literal `+` into a space, which
    /// silently corrupts the token and yields a confusing auth failure.
    func testEscapesPlusSoItIsNotDecodedAsSpace() {
        XCTAssertEqual(FormURLEncoding.body(["t": "a+b"]), "t=a%2Bb")
    }

    func testJoinsPairsInStableOrder() {
        let body = FormURLEncoding.body([
            "grant_type": "refresh_token",
            "client_id": "abc",
            "refresh_token": "xyz"
        ])
        XCTAssertEqual(body, "client_id=abc&grant_type=refresh_token&refresh_token=xyz")
    }

    func testEscapesKeysAsWellAsValues() {
        XCTAssertEqual(FormURLEncoding.body(["a b": "c d"]), "a%20b=c%20d")
    }
}
