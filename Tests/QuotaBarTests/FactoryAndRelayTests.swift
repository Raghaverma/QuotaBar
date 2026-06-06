import XCTest
import StatsUsageDomain
@testable import StatsUsage

final class ProviderFactoryRegistryTests: XCTestCase {
    func testEveryProviderTypeIsRegistered() {
        // The initializer's precondition would crash if any case were missing;
        // reaching this line proves full coverage.
        _ = ProviderFactoryRegistry()
        let makers = ProviderFactoryRegistry.makeDefaultMakers()
        XCTAssertEqual(Set(makers.keys), Set(ProviderType.allCases))
    }
}

final class RelayAdapterRegistryTests: XCTestCase {
    func testBundledGenericManifestLoads() {
        // Proves the resource is found regardless of how SwiftPM lays it out.
        let registry = RelayAdapterRegistry.loadFromBundle()
        XCTAssertNotNil(registry.manifest(id: "generic-newapi"),
                        "generic-newapi manifest must load from the bundle")
    }
}

final class RelayResponseInterpreterTests: XCTestCase {
    private func manifest() -> RelayAdapterManifest {
        RelayAdapterManifest(
            id: "generic-newapi",
            displayName: "Generic",
            match: .init(hostPatterns: ["*"], defaultBalanceChannelEnabled: true),
            setup: .init(requiredInputs: []),
            authStrategies: [],
            balanceRequest: .init(method: "GET", path: "/api/user/self",
                                  authHeader: "Authorization", authScheme: "Bearer", userIDHeader: "New-Api-User"),
            tokenRequest: nil,
            extract: .init(
                success: "success",
                remaining: "data.quota",
                used: "data.used_quota",
                limit: "add(data.quota,data.used_quota)",
                unit: "quota",
                accountLabel: #"coalesce(data.group,"Default Plan")"#
            ),
            postprocessID: nil
        )
    }

    func testInterpretsBalanceResponse() throws {
        let json = #"{"success":true,"data":{"quota":700,"used_quota":300,"group":"VIP"}}"#
        let snap = try RelayResponseInterpreter.interpret(
            data: Data(json.utf8), manifest: manifest(), providerID: "site", providerName: "Site"
        )
        XCTAssertEqual(snap.remaining, 700)
        XCTAssertEqual(snap.used, 300)
        XCTAssertEqual(snap.limit, 1000)
        XCTAssertEqual(snap.accountLabel, "VIP")
        XCTAssertEqual(snap.remainingPercent, 70)
    }

    func testSuccessFalseThrows() {
        let json = #"{"success":false,"data":{}}"#
        XCTAssertThrowsError(try RelayResponseInterpreter.interpret(
            data: Data(json.utf8), manifest: manifest(), providerID: "site", providerName: "Site"
        ))
    }
}
